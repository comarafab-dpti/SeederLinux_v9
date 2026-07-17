#!/bin/bash
# ============================================================================
# Core Script: core_session_gdm3.sh
# SeederLinux Lite - GDM3: logon/logoff (GNOME)
# ============================================================================
# Configura o GDM3 como display manager e define os scripts de logon
# e logoff que serao executados nas transicoes de sessao.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "14b - Configurar GDM3 (GNOME)"
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
if [ "$DISPLAY_MANAGER" != "gdm3" ]; then
    echo ">>> Display Manager nao e gdm3. Pulando este script."
    echo ">>> [14b] GDM3 nao configurado (DM diferente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Instalar GDM3
# ============================================================
echo ">>> Instalando GDM3..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y gdm3

# Garantir que o GDM3 seja o DM padrao
echo "gdm3 shared/default-x-display-manager select gdm3" | debconf-set-selections 2>/dev/null || true
echo "gdm3 gdm3/daemon_name string gdm3" | debconf-set-selections 2>/dev/null || true

# ============================================================
# Configurar GDM3
# ============================================================
echo ">>> Configurando GDM3..."
mkdir -p /etc/gdm3

cat > /etc/gdm3/daemon.conf <<EOF
# Configuracao GDM3 - SeederLinux
[daemon]
WaylandEnable=false
AutomaticLoginEnable=false
TimedLoginEnable=false

[security]
DisallowRoot=true

[greeter]
Session=${DESKTOP_ENV}
EOF

echo ">>> GDM3 configurado"

# ============================================================
# Configurar scripts de logon/logoff via PostSession/PreSession
# ============================================================
echo ">>> Configurando scripts de logon/logoff no GDM3..."

# PreSession - executado antes da sessao do usuario (logon)
PRESESSION_FILE="/etc/gdm3/PreSession/Default"
mkdir -p /etc/gdm3/PreSession

cat > "$PRESESSION_FILE" <<'PRESESSION'
#!/bin/bash
# PreSession do GDM3 - SeederLinux
# Executa o script de logon do SeederLinux
if [ -x /usr/local/bin/seederlinux-logon ]; then
    /usr/local/bin/seederlinux-logon "$@"
fi

exit 0
PRESESSION
chmod +x "$PRESESSION_FILE"

# PostSession - executado apos a sessao do usuario (logoff)
POSTSESSION_FILE="/etc/gdm3/PostSession/Default"
mkdir -p /etc/gdm3/PostSession

cat > "$POSTSESSION_FILE" <<'POSTSESSION'
#!/bin/bash
# PostSession do GDM3 - SeederLinux
# Executa o script de logoff do SeederLinux
if [ -x /usr/local/bin/seederlinux-logoff ]; then
    /usr/local/bin/seederlinux-logoff "$@"
fi

exit 0
POSTSESSION
chmod +x "$POSTSESSION_FILE"

echo ">>> Scripts de logon/logoff configurados no GDM3"

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
systemctl disable lightdm 2>/dev/null || true
systemctl disable sddm 2>/dev/null || true
systemctl enable gdm3

# ============================================================
# Reiniciar servico
# ============================================================
echo ">>> Reiniciando GDM3..."
systemctl restart gdm3 2>/dev/null || {
    echo ">>> AVISO: GDM3 sera iniciado no proximo boot."
}

echo ">>> [14b] GDM3 configurado!"
echo "============================================================"
