# Rclone Google Drive — Documentação de Configuração

> **Data:** 2026-09-05
> **Sistema:** Arch Linux (kernel 7.2.3-arch1-2)
> **Rclone:** v1.75.1
> **Ponto de montagem:** `/mnt/gdrive`

---

## Sumário

1. [Instalação do Rclone](#1-instalação-do-rclone)
2. [Configuração do Remote Google Drive](#2-configuração-do-remote-google-drive)
3. [Criação do Ponto de Montagem](#3-criação-do-ponto-de-montagem)
4. [Montagem Manual (teste)](#4-montagem-manual-teste)
5. [Serviço Systemd (auto-start)](#5-serviço-systemd-auto-start)
6. [Criação de Client ID Próprio (Google Cloud Console)](#6-criação-de-client-id-próprio-google-cloud-console)
7. [Atualização das Credenciais no Rclone](#7-atualização-das-credenciais-no-rclone)
8. [Comandos Úteis](#8-comandos-úteis)
9. [Arquivos de Configuração](#9-arquivos-de-configuração)
10. [Troubleshooting](#10-troubleshooting)

---

## 1. Instalação do Rclone

```bash
sudo pacman -S rclone
```

Verificar instalação:

```bash
rclone version
```

---

## 2. Configuração do Remote Google Drive

```bash
rclone config
```

Respostas durante a configuração interativa:

| Passo                              | Resposta                  |
| ---------------------------------- | ------------------------- |
| `n/s/q`                            | `n` (New remote)          |
| `name`                             | `gdrive`                  |
| `Storage`                          | `drive`                   |
| `client_id`                        | *(seu client_id próprio)* |
| `client_secret`                    | *(seu client_secret)*     |
| `scope`                            | `1` (Full access)         |
| `service_account_file`             | *(vazio)*                 |
| `Edit advanced config?`            | `n`                       |
| `Use web browser to authenticate?` | `y`                       |
| `Configure as Shared Drive?`       | `n`                       |
| `Keep this remote?`                | `y`                       |
| `Quit config`                      | `q`                       |

> **Nota:** Durante a autenticação via navegador, se estiver usando Client ID
> próprio, vai aparecer a tela "O Google não verificou este app". Clique em
> **Avançado** → **Acessar rclone (não seguro)** para autorizar.

---

## 3. Criação do Ponto de Montagem

```bash
sudo mkdir -p /mnt/gdrive
sudo chown $USER:$USER /mnt/gdrive
```

---

## 4. Montagem Manual (teste)

Para testar sem systemd:

```bash
rclone mount gdrive: /mnt/gdrive --vfs-cache-mode full &
```

Verificar se está montado:

```bash
df -h /mnt/gdrive
ls /mnt/gdrive/
```

Para desmontar:

```bash
fusermount3 -uz /mnt/gdrive
```

---

## 5. Serviço Systemd (auto-start)

### 5.1. Criar o arquivo do serviço

Arquivo: `~/.config/systemd/user/rclone-gdrive.service`

```ini
[Unit]
Description=Rclone mount Google Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=/usr/bin/mkdir -p /mnt/gdrive
ExecStart=/usr/bin/rclone mount gdrive: /mnt/gdrive \
    --vfs-cache-mode full \
    --vfs-cache-max-age 72h \
    --vfs-read-chunk-size 64M \
    --vfs-read-chunk-size-limit 2G \
    --buffer-size 64M \
    --dir-cache-time 72h \
    --log-level INFO \
    --log-file=/home/georgios/.local/share/rclone/gdrive.log
ExecStop=/usr/bin/fusermount3 -uz /mnt/gdrive
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

### 5.2. Ativar e iniciar o serviço

```bash
mkdir -p ~/.local/share/rclone
systemctl --user daemon-reload
systemctl --user enable rclone-gdrive.service
systemctl --user start rclone-gdrive.service
```

### 5.3. (Opcional) Iniciar no boot sem login

```bash
sudo loginctl enable-linger $USER
```

---

## 6. Criação de Client ID Próprio (Google Cloud Console)

> **Por quê?** O client_id compartilhado do rclone está sendo descontinuado em
> 2026. Criar o seu próprio garante funcionamento contínuo e cotas exclusivas.

### Passo a passo:

1. **Acessar** o [Google Cloud Console](https://console.cloud.google.com/).

2. **Criar novo projeto:**
   - Clique em "Selecione um projeto" (topo esquerdo) → "Novo Projeto".
   - Nome: `gdrive-rclone` (ou outro de sua escolha).

3. **Ativar a Google Drive API:**
   - Busque "Google Drive API" na barra de pesquisa.
   - Clique em **Ativar** (Enable).
   - Link direto: `https://console.developers.google.com/apis/api/drive.googleapis.com/overview?project=SEU_PROJECT_NUMBER`

4. **Configurar OAuth Consent Screen:**
   - Vá em **Google Auth Platform** → **Branding**.
   - Preencha: Nome do app (`rclone`), E-mail de suporte, Dados de contato do desenvolvedor.
   - Vá em **Acesso a dados** → Adicione o escopo: `https://www.googleapis.com/auth/drive`
   - Vá em **Público-alvo** → Adicione seu e-mail como usuário de teste.
   - Clique em **Publicar app** para evitar expiração semanal do token.

5. **Criar credenciais OAuth:**
   - Vá em **Clientes** (no menu da Google Auth Platform).
   - Clique em **Criar cliente** → Tipo: **Aplicativo para computador** (Desktop app).
   - Anote o **Client ID** e o **Client Secret** gerados.

### Após gerar as credenciais:

Anote o **Client ID** (termina em `.apps.googleusercontent.com`) e o **Client Secret** (começa com `GOCSPX-`).

> ⚠️ **Segurança:** Essas credenciais são pessoais e vinculadas à sua conta Google.
> Nunca as compartilhe publicamente nem as comite em repositórios.

---

## 7. Atualização das Credenciais no Rclone

Após gerar as chaves, atualizar o remote existente:

### 7.1. Inserir client_id e client_secret no config

Editar `~/.config/rclone/rclone.conf` e adicionar as linhas:

```ini
client_id = SEU_CLIENT_ID
client_secret = SEU_CLIENT_SECRET
```

Ou via Python:

```bash
python3 -c "
import configparser
config = configparser.ConfigParser()
config.read('$HOME/.config/rclone/rclone.conf')
config['gdrive']['client_id'] = 'SEU_CLIENT_ID'
config['gdrive']['client_secret'] = 'SEU_CLIENT_SECRET'
with open('$HOME/.config/rclone/rclone.conf', 'w') as f:
    config.write(f)
"
```

### 7.2. Reautenticar (gerar novo token com as novas chaves)

```bash
rclone config reconnect gdrive:
```

Responder `y` para substituir o token e `y` para autenticação via navegador.

### 7.3. Reiniciar o serviço

```bash
systemctl --user restart rclone-gdrive.service
```

---

## 8. Comandos Úteis

```bash
# Listar arquivos do Drive
rclone ls gdrive:

# Listar apenas diretórios
rclone lsd gdrive:

# Copiar arquivo para o Drive
rclone copy arquivo.txt gdrive:pasta/

# Sincronizar pasta local com o Drive
rclone sync /caminho/local gdrive:pasta/

# Ver status do serviço
systemctl --user status rclone-gdrive

# Reiniciar serviço
systemctl --user restart rclone-gdrive

# Parar serviço
systemctl --user stop rclone-gdrive

# Ver logs do serviço
journalctl --user -u rclone-gdrive

# Ver log do rclone
tail -f ~/.local/share/rclone/gdrive.log

# Desmontar manualmente
fusermount3 -uz /mnt/gdrive

# Listar remotes configurados
rclone listremotes
```

---

## 9. Arquivos de Configuração

| Arquivo                                              | Descrição                  |
| ---------------------------------------------------- | -------------------------- |
| `~/.config/rclone/rclone.conf`                       | Configuração do rclone     |
| `~/.config/systemd/user/rclone-gdrive.service`       | Serviço systemd do usuário |
| `~/.local/share/rclone/gdrive.log`                   | Log do rclone              |

### Conteúdo do rclone.conf (sem token):

```ini
[gdrive]
type = drive
scope = drive
team_drive =
client_id = SEU_CLIENT_ID.apps.googleusercontent.com
client_secret = GOCSPX-SEU_CLIENT_SECRET
token = {...}  # gerado automaticamente pela autenticação
```

---

## 10. Troubleshooting

### Erro: "Ponto final de transporte não está conectado"

O ponto de montagem ficou "preso" de uma sessão anterior.

```bash
fusermount3 -uz /mnt/gdrive
# Aguardar 1 segundo e remontar
systemctl --user restart rclone-gdrive.service
```

### Erro: "SERVICE_DISABLED" / "Google Drive API has not been used"

A API do Google Drive não está ativada no projeto. Ativar em:

```
https://console.developers.google.com/apis/api/drive.googleapis.com/overview?project=SEU_PROJECT_NUMBER
```

### Token expira toda semana

O app OAuth está em modo "Teste" no Google Cloud Console.
Solução: Ir em **Público-alvo** → clicar em **Publicar app**.

### Serviço não inicia no boot

Verificar se `linger` está ativado:

```bash
loginctl show-user $USER | grep Linger
# Se Linger=no:
sudo loginctl enable-linger $USER
```
