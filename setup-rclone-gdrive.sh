#!/usr/bin/env bash
# ==============================================================================
# setup-rclone-gdrive.sh
# Script para configurar o rclone com Google Drive no Arch Linux
#
# O que este script faz automaticamente:
#   1. Instala o rclone (se não estiver instalado)
#   2. Cria o ponto de montagem /mnt/gdrive
#   3. Grava o rclone.conf com client_id/client_secret
#   4. Abre o fluxo de autenticação OAuth no navegador
#   5. Cria e ativa o serviço systemd do usuário
#   6. Ativa linger para auto-start no boot
#
# Uso:
#   chmod +x setup-rclone-gdrive.sh
#   ./setup-rclone-gdrive.sh
#
# Pré-requisitos manuais (feitos uma única vez):
#   - Ter um projeto no Google Cloud Console com a Google Drive API ativada
#   - Ter um Client ID e Client Secret do tipo "Desktop app"
#   - Veja rclone-gdrive-docs.md seção 6 para o passo a passo
# ==============================================================================

set -euo pipefail

# ========================== CONFIGURAÇÕES =====================================

# Nome do remote no rclone
REMOTE_NAME="gdrive"

# Ponto de montagem
MOUNT_POINT="/mnt/gdrive"

# Credenciais OAuth — serão solicitadas ao usuário durante a execução
# (Gere no Google Cloud Console → Credenciais → ID do cliente OAuth → Desktop)
CLIENT_ID=""
CLIENT_SECRET=""

# Escopo de acesso ao Google Drive
# Opções: drive, drive.readonly, drive.file, drive.appfolder, drive.metadata.readonly
SCOPE="drive"

# Diretório de logs do rclone
LOG_DIR="$HOME/.local/share/rclone"
LOG_FILE="$LOG_DIR/gdrive.log"

# Arquivos de configuração
RCLONE_CONF="$HOME/.config/rclone/rclone.conf"
SYSTEMD_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_DIR/rclone-gdrive.service"

# =========================== CORES ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =========================== FUNÇÕES ==========================================

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $1"; }
error()   { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }
step()    { echo -e "\n${CYAN}══════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════════${NC}"; }


# ==============================================================================
# PASSO 0: Solicitar credenciais OAuth ao usuário
# ==============================================================================
prompt_credentials() {
    step "Passo 0/6 — Credenciais OAuth"

    if [[ -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
        success "Credenciais já definidas."
        return 0
    fi

    echo ""
    info "Você precisa de um Client ID e Client Secret do Google Cloud Console."
    info "Se ainda não tem, siga o passo a passo em rclone-gdrive-docs.md (seção 6)."
    info "Resumo rápido:"
    echo "  1. Acesse https://console.cloud.google.com/"
    echo "  2. Crie um projeto e ative a Google Drive API"
    echo "  3. Em Google Auth Platform → Clientes → Criar cliente (Desktop app)"
    echo "  4. Copie o Client ID e o Client Secret gerados"
    echo ""

    while [[ -z "$CLIENT_ID" ]]; do
        read -rp "Cole seu Client ID: " CLIENT_ID
        if [[ -z "$CLIENT_ID" ]]; then
            warn "Client ID não pode ser vazio."
        fi
    done

    while [[ -z "$CLIENT_SECRET" ]]; do
        read -rp "Cole seu Client Secret: " CLIENT_SECRET
        if [[ -z "$CLIENT_SECRET" ]]; then
            warn "Client Secret não pode ser vazio."
        fi
    done

    echo ""
    info "Client ID:     ${CLIENT_ID:0:20}..."
    info "Client Secret: ${CLIENT_SECRET:0:10}..."
    success "Credenciais recebidas!"
}

# ==============================================================================
# PASSO 1: Instalar rclone
# ==============================================================================
install_rclone() {
    step "Passo 1/6 — Instalação do rclone"

    if command -v rclone &>/dev/null; then
        success "rclone já instalado: $(rclone version | head -1)"
        return 0
    fi

    info "Instalando rclone via pacman..."
    sudo pacman -S --noconfirm rclone || error "Falha ao instalar rclone"
    success "rclone instalado: $(rclone version | head -1)"
}

# ==============================================================================
# PASSO 2: Criar ponto de montagem
# ==============================================================================
create_mount_point() {
    step "Passo 2/6 — Ponto de montagem"

    if [[ -d "$MOUNT_POINT" ]]; then
        success "Ponto de montagem já existe: $MOUNT_POINT"
    else
        info "Criando $MOUNT_POINT..."
        sudo mkdir -p "$MOUNT_POINT"
        success "Diretório criado: $MOUNT_POINT"
    fi

    info "Ajustando permissões para $USER..."
    sudo chown "$USER:$USER" "$MOUNT_POINT"
    success "Permissões ajustadas"
}

# ==============================================================================
# PASSO 3: Configurar rclone remote
# ==============================================================================
configure_rclone() {
    step "Passo 3/6 — Configuração do rclone"

    mkdir -p "$(dirname "$RCLONE_CONF")"

    # Verificar se o remote já existe
    if rclone listremotes 2>/dev/null | grep -q "^${REMOTE_NAME}:$"; then
        warn "Remote '$REMOTE_NAME' já existe."
        read -rp "Deseja sobrescrever a configuração? (s/N): " overwrite
        if [[ "${overwrite,,}" != "s" ]]; then
            info "Mantendo configuração existente."
            return 0
        fi
    fi

    info "Gravando configuração do remote '$REMOTE_NAME'..."

    # Grava o rclone.conf sem o token (será gerado na autenticação)
    cat > "$RCLONE_CONF" << EOF
[${REMOTE_NAME}]
type = drive
scope = ${SCOPE}
client_id = ${CLIENT_ID}
client_secret = ${CLIENT_SECRET}
team_drive =
EOF

    success "Configuração gravada em $RCLONE_CONF"
}

# ==============================================================================
# PASSO 4: Autenticação OAuth (requer navegador)
# ==============================================================================
authenticate_rclone() {
    step "Passo 4/6 — Autenticação com Google"

    # Verificar se já tem token válido
    if rclone lsd "${REMOTE_NAME}:" &>/dev/null 2>&1; then
        success "Remote '$REMOTE_NAME' já está autenticado e funcional."
        return 0
    fi

    echo ""
    warn "O navegador vai abrir para você fazer login na conta Google."
    warn "Se aparecer 'O Google não verificou este app':"
    warn "  → Clique em 'Avançado'"
    warn "  → Clique em 'Acessar rclone (não seguro)'"
    echo ""
    read -rp "Pressione ENTER para continuar..."

    info "Iniciando autenticação OAuth..."
    rclone config reconnect "${REMOTE_NAME}:" || error "Falha na autenticação"

    # Verificar se a autenticação foi bem-sucedida
    if rclone lsd "${REMOTE_NAME}:" &>/dev/null 2>&1; then
        success "Autenticação concluída com sucesso!"
        echo ""
        info "Seus diretórios no Google Drive:"
        rclone lsd "${REMOTE_NAME}:" 2>/dev/null | awk '{print "  📁 " $NF}'
    else
        error "Autenticação falhou. Verifique se a Google Drive API está ativada no seu projeto."
    fi
}

# ==============================================================================
# PASSO 5: Criar e ativar serviço systemd
# ==============================================================================
setup_systemd_service() {
    step "Passo 5/6 — Serviço systemd"

    # Criar diretórios necessários
    mkdir -p "$SYSTEMD_DIR"
    mkdir -p "$LOG_DIR"

    # Desmontar se já estiver montado (evita conflito)
    fusermount3 -uz "$MOUNT_POINT" 2>/dev/null || true

    info "Criando serviço systemd..."

    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Rclone mount Google Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=/usr/bin/mkdir -p ${MOUNT_POINT}
ExecStart=/usr/bin/rclone mount ${REMOTE_NAME}: ${MOUNT_POINT} \\
    --vfs-cache-mode full \\
    --vfs-cache-max-age 72h \\
    --vfs-read-chunk-size 64M \\
    --vfs-read-chunk-size-limit 2G \\
    --buffer-size 64M \\
    --dir-cache-time 72h \\
    --log-level INFO \\
    --log-file=${LOG_FILE}
ExecStop=/usr/bin/fusermount3 -uz ${MOUNT_POINT}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

    success "Serviço criado: $SERVICE_FILE"

    info "Recarregando systemd..."
    systemctl --user daemon-reload

    info "Habilitando serviço para iniciar no login..."
    systemctl --user enable rclone-gdrive.service

    info "Iniciando serviço..."
    systemctl --user start rclone-gdrive.service

    # Aguardar montagem
    sleep 3

    # Verificar status
    if systemctl --user is-active --quiet rclone-gdrive.service; then
        success "Serviço iniciado com sucesso!"
        echo ""
        systemctl --user status rclone-gdrive.service --no-pager | head -10
    else
        error "Serviço falhou ao iniciar. Verifique: journalctl --user -u rclone-gdrive"
    fi
}

# ==============================================================================
# PASSO 6: Ativar linger (auto-start no boot)
# ==============================================================================
enable_linger() {
    step "Passo 6/6 — Auto-start no boot"

    local linger_status
    linger_status=$(loginctl show-user "$USER" --property=Linger 2>/dev/null | cut -d= -f2)

    if [[ "$linger_status" == "yes" ]]; then
        success "Linger já está ativado para $USER"
    else
        info "Ativando linger para que o serviço inicie no boot..."
        sudo loginctl enable-linger "$USER"
        success "Linger ativado"
    fi
}

# ==============================================================================
# VERIFICAÇÃO FINAL
# ==============================================================================
verify_installation() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Verificação Final${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo ""

    local all_ok=true

    # Verificar rclone
    if command -v rclone &>/dev/null; then
        success "rclone instalado"
    else
        error "rclone NÃO encontrado"; all_ok=false
    fi

    # Verificar montagem
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        success "Google Drive montado em $MOUNT_POINT"
        echo "     $(df -h "$MOUNT_POINT" | tail -1 | awk '{print "Espaço: " $2 " total, " $3 " usado, " $4 " disponível"}')"
    else
        warn "Montagem não detectada em $MOUNT_POINT"; all_ok=false
    fi

    # Verificar serviço
    if systemctl --user is-active --quiet rclone-gdrive.service; then
        success "Serviço systemd ativo"
    else
        warn "Serviço systemd inativo"; all_ok=false
    fi

    # Verificar linger
    local linger_status
    linger_status=$(loginctl show-user "$USER" --property=Linger 2>/dev/null | cut -d= -f2)
    if [[ "$linger_status" == "yes" ]]; then
        success "Linger ativado (auto-start no boot)"
    else
        warn "Linger NÃO ativado"
    fi

    echo ""
    if $all_ok; then
        echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅ Configuração concluída com sucesso!      ║${NC}"
        echo -e "${GREEN}║  Seus arquivos estão em: $MOUNT_POINT       ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    else
        echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  ⚠️  Configuração parcial. Verifique avisos. ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
    fi

    echo ""
    info "Comandos úteis:"
    echo "  Ver status:      systemctl --user status rclone-gdrive"
    echo "  Reiniciar:       systemctl --user restart rclone-gdrive"
    echo "  Ver logs:        tail -f $LOG_FILE"
    echo "  Listar arquivos: ls $MOUNT_POINT/"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  Setup Rclone Google Drive — Arch Linux      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo ""

    prompt_credentials
    install_rclone
    create_mount_point
    configure_rclone
    authenticate_rclone
    setup_systemd_service
    enable_linger
    verify_installation
}

main "$@"
