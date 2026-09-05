# gdrive-rclone
Script em bash que automatiza todo o processo de montar o Google Drive no Linux como disco local. Ele cuida da instalação do Rclone, pede suas credenciais OAuth de forma segura, configura o cache VFS pra abrir arquivos pesados sem engasgar e cria o serviço no systemd pra tudo subir sozinho no boot.
