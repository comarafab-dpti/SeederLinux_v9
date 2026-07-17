#!/bin/bash
# ============================================================================
# Core Script: core_session_lightdm.sh
# SeederLinux Lite - LightDM: logon/logoff (MATE, Cinnamon, XFCE, LXDE)
# ============================================================================
# Configura o LightDM como display manager e define os scripts de logon
# e logoff que serao executados nas transicoes de sessao.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "14a - Configurar LightDM (MATE, Cinnamon, XFCE, LXDE)"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
DISPLAY_MANAGER="{{DISPLAY_MANAGER}}"
DESKTOP_ENV="{{DESKTOP_ENV}}"
BASE_URL="{{BASE_URL}}"
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
GRUPO_ADMIN_AD="{{GRUPO_ADMIN_AD}}"

echo ">>> Display Manager: $DISPLAY_MANAGER"
echo ">>> Ambiente: $DESKTOP_ENV"

# ============================================================
# Detectar Display Manager ativo (se nao definido)
# ============================================================
if [ -z "$DISPLAY_MANAGER" ] || [ "$DISPLAY_MANAGER" = "" ]; then
    if systemctl is-active --quiet lightdm 2>/dev/null; then DISPLAY_MANAGER="lightdm"
    elif systemctl is-active --quiet gdm3 2>/dev/null; then DISPLAY_MANAGER="gdm3"
    elif systemctl is-active --quiet sddm 2>/dev/null; then DISPLAY_MANAGER="sddm"
    elif [ -f /etc/X11/default-display-manager ]; then
        DISPLAY_MANAGER="$(basename "$(cat /etc/X11/default-display-manager)")"
    elif command -v cinnamon-session &>/dev/null || command -v mate-session &>/dev/null || command -v startxfce4 &>/dev/null; then
        DISPLAY_MANAGER="lightdm"
    elif command -v gnome-session &>/dev/null; then
        DISPLAY_MANAGER="gdm3"
    elif command -v startplasma-x11 &>/dev/null; then
        DISPLAY_MANAGER="sddm"
    else
        DISPLAY_MANAGER="lightdm"
    fi
    echo ">>> Display Manager detectado: $DISPLAY_MANAGER"
fi

# ============================================================
# Verificar se este script deve ser executado
# ============================================================
if [ "$DISPLAY_MANAGER" != "lightdm" ]; then
    echo ">>> Display Manager nao e lightdm. Pulando este script."
    echo ">>> [14a] LightDM nao configurado (DM diferente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Instalar LightDM
# ============================================================
echo ">>> Instalando LightDM..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y lightdm lightdm-gtk-greeter

# Garantir que o LightDM seja o DM padrao
echo "lightdm shared/default-x-display-manager select lightdm" | debconf-set-selections 2>/dev/null || true
echo "lightdm lightdm/daemon_name string lightdm" | debconf-set-selections 2>/dev/null || true

# ============================================================
# Configurar LightDM
# ============================================================
echo ">>> Configurando LightDM..."
mkdir -p /etc/lightdm

cat > /etc/lightdm/lightdm.conf <<EOF
# Configuracao LightDM - SeederLinux
[Seat:*]
greeter-session=lightdm-gtk-greeter
user-session=${DESKTOP_ENV}
allow-guest=false
greeter-hide-users=true
greeter-show-manual-login=true
session-wrapper=/etc/lightdm/Xsession
pam-service=lightdm
pam-autologin-service=lightdm-autologin

# Executar scripts de logon/logoff
session-setup-script=/usr/local/bin/seederlinux-logon
session-cleanup-script=/usr/local/bin/seederlinux-logoff
EOF

echo ">>> LightDM configurado"

# ============================================================
# Configurar greeter do LightDM
# ============================================================
echo ">>> Configurando greeter..."
mkdir -p /etc/lightdm

cat > /etc/lightdm/lightdm-gtk-greeter.conf <<EOF
[greeter]
theme-name = {{THEME}}
icon-theme-name = Adwaita
font-name = DejaVu Sans 10
background = /usr/share/backgrounds/seederlinux/wallpaper-login.jpg
logo = /usr/share/pixmaps/seederlinux-logo.png
show-indicators = ~host;~spacer;~clock;~spacer;~session;~spacer;~power
EOF

echo ">>> Greeter configurado"

# ============================================================
# Configurar Xsession
# ============================================================
echo ">>> Configurando Xsession..."
if [ ! -f /etc/lightdm/Xsession ]; then
    cat > /etc/lightdm/Xsession <<'XSESSION'
#!/bin/bash
# Xsession do SeederLinux para LightDM
exec /etc/X11/Xsession "$@"
XSESSION
    chmod +x /etc/lightdm/Xsession
fi

# ============================================================
# Garantir que os scripts de logon/logoff existam
# ============================================================
echo ">>> Verificando scripts de logon/logoff..."
for SCRIPT in seederlinux-logon seederlinux-logoff; do
    if [ ! -f "/usr/local/bin/${SCRIPT}" ]; then
        echo ">>> AVISO: /usr/local/bin/${SCRIPT} nao encontrado."
        echo ">>> Os scripts core_logon.sh e core_logoff.sh devem ser executados antes."
    fi
done

# ============================================================
# Desabilitar outros display managers
# ============================================================
echo ">>> Desabilitando outros display managers..."
systemctl disable gdm3 2>/dev/null || true
systemctl disable sddm 2>/dev/null || true
systemctl enable lightdm

# ============================================================
# Reiniciar servico
# ============================================================
echo ">>> Reiniciando LightDM..."
systemctl restart lightdm 2>/dev/null || {
    echo ">>> AVISO: LightDM sera iniciado no proximo boot."
}

echo ">>> [14a] LightDM configurado!"
echo "============================================================"
