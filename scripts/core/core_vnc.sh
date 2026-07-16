#!/bin/bash
# ============================================================================
# Core Script: core_vnc.sh
# SeederLinux Lite - x11vnc
# ============================================================================
# Instala e configura o x11vnc para suporte remoto, incluindo servico
# systemd e senha de acesso.
#
# SEGURANCA: A senha VNC e gravada em /etc/seederlinux/secrets.env
# (perm 600) e usada diretamente com x11vnc -storepasswd. A senha
# NUNCA aparece em texto plano no bundle, nos logs ou em variaveis
# exportadas. O placeholder {{VNC_PASSWORD}} e substituido por vazio
# no bundle - a senha real e passada apenas para o storepasswd.
#
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "09 - Configurar x11vnc"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
VNC_ENABLED="{{VNC_ENABLED}}"
VNC_PASSWORD="{{VNC_PASSWORD}}"
DISPLAY_MANAGER="{{DISPLAY_MANAGER}}"

echo ">>> VNC habilitado: $VNC_ENABLED"

# ============================================================
# Verificar se VNC esta habilitado
# ============================================================
if [ "$VNC_ENABLED" != "true" ]; then
    echo ">>> VNC desativado. Pulando configuracao."
    echo ">>> [09] x11vnc desativado."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Instalar x11vnc
# ============================================================
echo ">>> Instalando x11vnc..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y x11vnc

# ============================================================
# Configurar senha do VNC (SEM expor em texto plano)
# ============================================================
echo ">>> Configurando senha do VNC..."
mkdir -p /etc/x11vnc
mkdir -p /etc/seederlinux

SECRETS_FILE="/etc/seederlinux/secrets.env"

# Gravar a senha no arquivo de secrets (perm 600)
# O placeholder {{VNC_PASSWORD}} foi substituido pelo valor real
# pelo sistema. Se vazio, gerar senha aleatoria.
if [ -n "$VNC_PASSWORD" ] && [ "$VNC_PASSWORD" != "" ]; then
    # Usar a senha fornecida na configuracao da OM
    x11vnc -storepasswd "$VNC_PASSWORD" /etc/x11vnc/vncpasswd
    chmod 600 /etc/x11vnc/vncpasswd
    echo ">>> Senha VNC configurada (fornecida pela OM)"

    # Gravar referencia no secrets.env (apenas o fato de que existe,
    # NAO a senha em texto plano)
    echo "VNC_PASSWORD_SET=true" >> "$SECRETS_FILE"
else
    echo ">>> VNC_PASSWORD nao definido. Gerando senha aleatoria."
    RANDOM_PASS=$(openssl rand -base64 12)
    x11vnc -storepasswd "$RANDOM_PASS" /etc/x11vnc/vncpasswd
    chmod 600 /etc/x11vnc/vncpasswd
    echo ">>> Senha VNC gerada com sucesso"

    echo "VNC_PASSWORD_SET=true" >> "$SECRETS_FILE"
fi

chmod 600 "$SECRETS_FILE" 2>/dev/null || true

# Limpar a variavel de senha da memoria para evitar vazamento
unset VNC_PASSWORD
unset RANDOM_PASS

# ============================================================
# Criar servico systemd para x11vnc
# ============================================================
echo ">>> Criando servico systemd x11vnc..."

# Determinar o display e o auth file conforme o display manager
case "$DISPLAY_MANAGER" in
    lightdm)
        VNC_DISPLAY=":0"
        VNC_AUTH="/var/run/lightdm/root/:0"
        ;;
    gdm3)
        VNC_DISPLAY=":0"
        VNC_AUTH="/run/user/0/gdm/Xauthority"
        ;;
    sddm)
        VNC_DISPLAY=":0"
        VNC_AUTH="/var/run/sddm/:0"
        ;;
    *)
        VNC_DISPLAY=":0"
        VNC_AUTH="/tmp/.X0-lock"
        ;;
esac

cat > /etc/systemd/system/x11vnc.service <<EOF
[Unit]
Description=x11vnc Server - SeederLinux
After=display-manager.service
Requires=display-manager.service

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -display ${VNC_DISPLAY} -auth ${VNC_AUTH} -forever -loop -noxdamage -repeat -rfbauth /etc/x11vnc/vncpasswd -rfbport 5900 -shared -bg -o /var/log/x11vnc.log
ExecStop=/usr/bin/killall x11vnc
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

systemctl daemon-reload
systemctl enable x11vnc.service
systemctl start x11vnc.service 2>/dev/null || {
    echo ">>> AVISO: Nao foi possivel iniciar x11vnc agora."
    echo ">>> O servico sera iniciado apos o display manager."
}

echo ">>> [09] x11vnc configurado!"
echo "============================================================"
