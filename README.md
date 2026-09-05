# Rclone Google Drive Mount - Arch Linux

Um jeito simples e direto de montar o Google Drive como se fosse uma pasta local no Arch Linux, usando Rclone e systemd pra subir tudo sozinho no boot.

---

## O que tem aqui?

- Monta o Google Drive direto em `/mnt/gdrive` (ou onde você preferir).
- Sobe sozinho no boot com um serviço de usuário do systemd (`systemd --user`), sem precisar logar na interface toda vez.
- Usa cache VFS completo (`--vfs-cache-mode full`), então dá pra editar arquivos no VSCode, salvar direto pelo navegador ou rodar scripts como se estivesse tudo no seu SSD.
- Suporte ao seu próprio Client ID do Google, evitando lentidão e limite de requisições da chave padrão do Rclone.
- O script é interativo e não salva nenhuma chave no código, então dá pra compartilhar esse repo numa boa.

---

## Estrutura dos arquivos

```text
.
├── setup-rclone-gdrive.sh    # Script que faz toda a mágica sozinho
├── rclone-gdrive-docs.md     # Guia manual detalhado e troubleshooting
└── README.md                 # Este arquivo de apresentação e guia rápido
```

---

## O que você precisa antes de começar

1. **Arch Linux** (ou derivados. Se usar Debian/Ubuntu, é só trocar o `pacman` por `apt` no script).
2. **Suporte a FUSE** (`fuse3` ou `fuse2` instalados).
3. **Acesso sudo** (só pra instalar o rclone caso falte e criar a pasta `/mnt/gdrive`).
4. **Client ID e Client Secret do Google** (tipo "App para computador / Desktop app"). Se ainda não tem, relaxa que tem o passo a passo logo abaixo.

---

## Como rodar (Passo a passo rápido)

### 1. Dê permissão de execução pro script

```bash
chmod +x setup-rclone-gdrive.sh
```

### 2. Execute o script

```bash
./setup-rclone-gdrive.sh
```

### 3. O que vai acontecer:

1. O script vai te pedir o **Client ID** e o **Client Secret** direto no terminal.
2. Vai checar se o `rclone` tá instalado (e instala se não tiver).
3. Cria a pasta `/mnt/gdrive` e ajusta as permissões pro seu usuário.
4. Monta o arquivo `~/.config/rclone/rclone.conf` com as configs certas.
5. Abre o navegador pra você autorizar sua conta do Google com dois cliques.
6. Cria o serviço no systemd (`rclone-gdrive.service`), ativa e inicia na hora.
7. Roda um `loginctl enable-linger` pro drive já montar logo que a máquina ligar.
8. Faz um teste rápido de leitura/escrita pra garantir que tá tudo 100%.

---

## Como pegar suas credenciais no Google (Se ainda não tiver)

Usar credenciais próprias é o grande segredo pro rclone rodar liso sem tomar erro de cota:

1. Entra no [Google Cloud Console](https://console.cloud.google.com/).
2. Cria um projeto qualquer (ex: `Meu Rclone`).
3. Vai em **APIs e Serviços** > **Biblioteca**, procura por **Google Drive API** e clica em **Ativar**.
4. Na aba **Tela de consentimento OAuth**:
   - Escolhe **Externo**.
   - Coloca qualquer nome de app e seu email.
   - Em **Usuários de teste**, adiciona o seu próprio Gmail.
5. Vai em **Credenciais** > **Criar Credenciais** > **ID do cliente OAuth**:
   - Escolhe o tipo **App para computador** (Desktop app).
6. Copia o **Client ID** e o **Client Secret** que ele te der e cola quando o script pedir.

Se quiser ver cada detalhe com calma, dá uma olhada na seção 6 do [rclone-gdrive-docs.md](./rclone-gdrive-docs.md).

---

## Comandos úteis pro dia a dia

O rclone fica rodando de boa em segundo plano pelo systemd do seu usuário. Pra controlar ele:

| O que você quer fazer | Comando |
| :--- | :--- |
| Ver se tá rodando | `systemctl --user status rclone-gdrive.service` |
| Iniciar a montagem | `systemctl --user start rclone-gdrive.service` |
| Parar a montagem | `systemctl --user stop rclone-gdrive.service` |
| Reiniciar | `systemctl --user restart rclone-gdrive.service` |
| Ver os logs em tempo real | `journalctl --user -u rclone-gdrive.service -f` |
| Desmontar no braço | `fusermount -u /mnt/gdrive` |

---

## Por que o cache tá configurado assim?

O serviço usa algumas flags pensadas pra uso diário sem travar o sistema:

- `--vfs-cache-mode full`: Faz o drive se comportar igualzinho a um HD ou SSD local.
- `--vfs-cache-max-size 50G`: Impede o rclone de comer todo o seu disco com cache.
- `--vfs-cache-max-age 24h`: Remove do cache o que você não mexe há mais de um dia.
- `--dir-cache-time 72h`: Deixa a navegação entre pastas instantânea guardando a árvore em memória.

---

## Deu ruim? (Troubleshooting rápido)

### Pasta ocupada (`Device or resource busy`)
Às vezes fica algum processo preso. Só forçar a desmontagem:
```bash
fusermount -u /mnt/gdrive || sudo umount -l /mnt/gdrive
systemctl --user restart rclone-gdrive.service
```

### Erro de permissão com FUSE
Dá uma olhada no `/etc/fuse.conf`. Garanta que a linha abaixo existe e não está comentada com `#`:
```text
user_allow_other
```

### O token expirou ou perdeu acesso
Só mandar o rclone renovar:
```bash
rclone config reconnect gdrive:
```

---

## Dica de segurança

- O script `setup-rclone-gdrive.sh` foi feito pra ser seguro e não guarda nada fixo.
- As credenciais ficam salvas apenas no seu `~/.config/rclone/rclone.conf` local.
- Se for mandar seus arquivos pro GitHub, lembre-se de nunca commitar arquivos com suas chaves ou seus tokens do rclone.

---

## Licença

MIT - pode usar, alterar e compartilhar à vontade.
