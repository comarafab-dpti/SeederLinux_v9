#!/bin/bash
# ============================================================================
# Core Script: core_logon.sh
# SeederLinux Lite - Logon multi-DE
# ============================================================================
# Script executado no momento do login do usuario. Cria o script permanente
# /usr/local/bin/seederlinux-logon que sera chamado pelo display manager
# (LightDM/GDM3/SDDM) a cada login, apos reboot.
#
# O script permanente detecta automaticamente o ambiente grafico e aplica
# configuracoes especificas via case. Le as variaveis de
# /etc/seederlinux/config.env (persistente).
#
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "14 - Logon do usuario (multi-DE)"
echo "============================================================"

# ============================================================
# Variaveis (substituidas no bundle)
# ============================================================
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
SERVIDOR_ARQUIVOS="{{SERVIDOR_ARQUIVOS}}"
COMPARTILHAMENTOS="{{COMPARTILHAMENTOS}}"
MOUNT_BASE="{{MOUNT_BASE}}"
HOMEPAGE="{{HOMEPAGE}}"
OM_ACRONYM="{{OM_ACRONYM}}"
DESKTOP_ENV="{{DESKTOP_ENV}}"
DEFAULT_PRINTER="{{DEFAULT_PRINTER}}"
PROXY_URL="{{PROXY_URL}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
NO_PROXY="{{NO_PROXY}}"
THEME="{{THEME}}"

# ============================================================
# Detectar ambiente grafico se nao definido
# ============================================================
if [ -z "$DESKTOP_ENV" ] || [ "$DESKTOP_ENV" = "" ]; then
    if command -v cinnamon-session &>/dev/null; then DESKTOP_ENV="cinnamon"
    elif command -v mate-session &>/dev/null; then DESKTOP_ENV="mate"
    elif command -v gnome-session &>/dev/null; then DESKTOP_ENV="gnome"
    elif command -v startxfce4 &>/dev/null; then DESKTOP_ENV="xfce"
    elif command -v startplasma-x11 &>/dev/null; then DESKTOP_ENV="kde"
    elif command -v startlxde &>/dev/null; then DESKTOP_ENV="lxde"
    else DESKTOP_ENV="unknown"
    fi
    echo ">>> DE detectado automaticamente: $DESKTOP_ENV"
fi

# ============================================================
# 1. Criar o script PERMANENTE em /usr/local/bin/seederlinux-logon
#    Este script sera chamado pelo LightDM/GDM3/SDDM a cada login
#    e le as variaveis de /etc/seederlinux/config.env
# ============================================================
echo ">>> Criando script permanente: /usr/local/bin/seederlinux-logon"

cat > /usr/local/bin/seederlinux-logon <<'PERMSCRIPT'
#!/bin/bash
# seederlinux-logon - Script permanente de logon do SeederLinux (multi-DE)
# Executado pelo display manager (LightDM/GDM3/SDDM) a cada login.
# Le as variaveis de /etc/seederlinux/config.env (persistente).

CONFIG_FILE="/etc/seederlinux/config.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo ">>> [logon] AVISO: $CONFIG_FILE nao encontrado. Logon sem configuracao."
    exit 0
fi

USERNAME="${USER:-$(whoami)}"
USER_HOME="${HOME:-/home/$USERNAME}"
LOG_DIR="/var/log/logon-logoff"
LOG_FILE="$LOG_DIR/logon_${USERNAME}.log"

mkdir -p "$LOG_DIR"
chmod 1777 "$LOG_DIR"

# ============================================================
# Funcoes de deteccao de ambiente
# ============================================================
detect_de() {
    if command -v cinnamon-session &>/dev/null; then echo "cinnamon"
    elif command -v mate-session &>/dev/null; then echo "mate"
    elif command -v gnome-session &>/dev/null; then echo "gnome"
    elif command -v startxfce4 &>/dev/null; then echo "xfce"
    elif command -v startplasma-x11 &>/dev/null; then echo "kde"
    elif command -v startlxde &>/dev/null; then echo "lxde"
    else echo "unknown"
    fi
}

detect_dm() {
    if systemctl is-active --quiet lightdm 2>/dev/null; then echo "lightdm"
    elif systemctl is-active --quiet gdm3 2>/dev/null; then echo "gdm3"
    elif systemctl is-active --quiet sddm 2>/dev/null; then echo "sddm"
    else echo "unknown"
    fi
}

DESKTOP_ENV=$(detect_de)
DISPLAY_MANAGER=$(detect_dm)

exec >> "$LOG_FILE" 2>&1
echo "=== Logon: $(date) - Usuario: $USERNAME - Ambiente: $DESKTOP_ENV - DM: $DISPLAY_MANAGER ==="

# ============================================================
# Configuracoes COMUNS (executam em qualquer DE)
# ============================================================

# Criar diretorios base do usuario
mkdir -p "$USER_HOME/Desktop" "$USER_HOME/Downloads" "$USER_HOME/Documents"
mkdir -p "$USER_HOME/.config" "$USER_HOME/.local/share/applications"
mkdir -p "$USER_HOME/.java/deployment/security"

# Ajustar dono da home
chown -R "$USERNAME:$(id -gn)" "$USER_HOME" 2>/dev/null || true

# ============================================================
# Mapear compartilhamentos CIFS
# ============================================================
if [ -n "$SERVIDOR_ARQUIVOS" ] && [ "$SERVIDOR_ARQUIVOS" != "" ]; then
    MOUNT_DIR="${MOUNT_BASE:-/mnt}"
    mkdir -p "$MOUNT_DIR"

    if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
        for SHARE in $COMPARTILHAMENTOS; do
            SHARE_MOUNT="${MOUNT_DIR}/${SHARE}"
            mkdir -p "$SHARE_MOUNT"

            mountpoint -q "$SHARE_MOUNT" 2>/dev/null || {
                mount -t cifs "//${SERVIDOR_ARQUIVOS}/${SHARE}" "$SHARE_MOUNT" \
                    -o "username=${USERNAME},domain=${DOMINIO_NETBIOS},uid=$(id -u),gid=$(id -g),iocharset=utf8,vers=3.0" 2>/dev/null || {
                    echo ">>> [logon] AVISO: Falha ao montar //${SERVIDOR_ARQUIVOS}/${SHARE}"
                }
            }
            echo ">>> [logon] Compartilhamento montado: ${SHARE}"

            cat > "$USER_HOME/Desktop/${SHARE}.desktop" <<EOF
[Desktop Entry]
Type=Link
Name=${SHARE}
URL=file://${SHARE_MOUNT}
Icon=folder
EOF
            chmod +x "$USER_HOME/Desktop/${SHARE}.desktop" 2>/dev/null || true
        done
    fi
fi

# ============================================================
# Configurar impressora padrao
# ============================================================
if [ -n "$DEFAULT_PRINTER" ] && [ "$DEFAULT_PRINTER" != "" ]; then
    lpoptions -d "$DEFAULT_PRINTER" 2>/dev/null || true
fi

# ============================================================
# Criar atalho do portal no desktop
# ============================================================
if [ -n "$HOMEPAGE" ] && [ "$HOMEPAGE" != "" ]; then
    cat > "$USER_HOME/Desktop/Portal-${OM_ACRONYM}.desktop" <<EOF
[Desktop Entry]
Type=Link
Name=Portal ${OM_ACRONYM}
URL=${HOMEPAGE}
Icon=firefox-esr
EOF
    chmod +x "$USER_HOME/Desktop/Portal-${OM_ACRONYM}.desktop" 2>/dev/null || true
fi

# ============================================================
# Criar atalhos de aplicativos no desktop
# ============================================================
# Chrome
if command -v google-chrome &>/dev/null || command -v google-chrome-stable &>/dev/null; then
    cat > "$USER_HOME/Desktop/Google-Chrome.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=google-chrome-stable
Icon=google-chrome
Categories=Network;
EOF
    chmod +x "$USER_HOME/Desktop/Google-Chrome.desktop" 2>/dev/null || true
fi

# Firefox ESR
if command -v firefox-esr &>/dev/null; then
    cat > "$USER_HOME/Desktop/Firefox-ESR.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Firefox ESR
Exec=firefox-esr
Icon=firefox-esr
Categories=Network;
EOF
    chmod +x "$USER_HOME/Desktop/Firefox-ESR.desktop" 2>/dev/null || true
fi

# OnlyOffice
if command -v onlyoffice-desktopeditors &>/dev/null; then
    cat > "$USER_HOME/Desktop/OnlyOffice.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=OnlyOffice
Exec=onlyoffice-desktopeditors
Icon=onlyoffice-desktopeditors
Categories=Office;
EOF
    chmod +x "$USER_HOME/Desktop/OnlyOffice.desktop" 2>/dev/null || true
fi

# ============================================================
# Configurar politicas do Firefox (user.js)
# ============================================================
FIREFOX_PROFILES=$(find "$USER_HOME/.mozilla/firefox" -maxdepth 1 -name "*.default*" -type d 2>/dev/null)
for PROFILE in $FIREFOX_PROFILES; do
    cat > "$PROFILE/user.js" <<EOF
user_pref("browser.startup.homepage", "${HOMEPAGE}");
user_pref("network.proxy.type", 2);
user_pref("network.proxy.autoconfig_url", "${PAC_URL:-}");
user_pref("network.proxy.http", "${PROXY_HTTP:-}");
user_pref("network.proxy.http_port", ${PROXY_PORTA:-0});
user_pref("network.proxy.no_proxies_on", "${NO_PROXY:-localhost,127.0.0.1}");
user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 51200);
user_pref("app.update.enabled", false);
EOF
    chown "$USERNAME:$(id -gn)" "$PROFILE/user.js" 2>/dev/null || true
done

# ============================================================
# Configurar politicas do Chrome/Chromium (master_preferences)
# ============================================================
CHROME_PREFS="/etc/opt/chrome/policies/managed/seederlinux.json"
if [ -d "/etc/opt/chrome/policies/managed" ]; then
    cat > "$CHROME_PREFS" <<EOF
{
    "HomepageLocation": "${HOMEPAGE}",
    "HomepageIsNewTabPage": false,
    "ProxyMode": "fixed_servers",
    "ProxyServer": "${PROXY_HTTP}:${PROXY_PORTA}",
    "ProxyBypassList": "${NO_PROXY:-localhost,127.0.0.1}",
    "AutoSelectCertificateForUrls": ["*"],
    "DefaultBrowserSettingEnabled": false
}
EOF
fi

CHROMIUM_PREFS="/etc/chromium/policies/managed/seederlinux.json"
if [ -d "/etc/chromium/policies/managed" ]; then
    cat > "$CHROMIUM_PREFS" <<EOF
{
    "HomepageLocation": "${HOMEPAGE}",
    "HomepageIsNewTabPage": false,
    "ProxyMode": "fixed_servers",
    "ProxyServer": "${PROXY_HTTP}:${PROXY_PORTA}",
    "ProxyBypassList": "${NO_PROXY:-localhost,127.0.0.1}",
    "DefaultBrowserSettingEnabled": false
}
EOF
fi

# ============================================================
# Configurar excecoes Java (exception.sites)
# ============================================================
JAVA_EXC="$USER_HOME/.java/deployment/security/exception.sites"
cat > "$JAVA_EXC" <<EOF
${HOMEPAGE}
${BASE_URL:-}
${OCS_SERVER:-}
${GLPI_SERVER:-}
EOF
chown "$USERNAME:$(id -gn)" "$JAVA_EXC" 2>/dev/null || true

# ============================================================
# Corrigir permissoes de sudo/su/pkexec
# ============================================================
if [ -f /etc/sudoers ]; then
    chmod 440 /etc/sudoers 2>/dev/null || true
fi

# ============================================================
# Configuracoes ESPECIFICAS por DE
# ============================================================
WALLPAPER_PATH="/usr/share/backgrounds/seederlinux/wallpaper.jpg"

case "$DESKTOP_ENV" in
    cinnamon)
        gsettings set org.cinnamon.desktop.background picture-uri "file://$WALLPAPER_PATH" 2>/dev/null || true
        gsettings set org.cinnamon.desktop.background picture-options 'zoom' 2>/dev/null || true
        gsettings set org.cinnamon.desktop.interface gtk-theme "${THEME:-Adwaita}" 2>/dev/null || true
        gsettings set org.cinnamon.desktop.interface icon-theme 'Adwaita' 2>/dev/null || true
        gsettings set org.cinnamon.sounds event-sounds false 2>/dev/null || true
        ;;
    mate)
        gsettings set org.mate.background picture-filename "$WALLPAPER_PATH" 2>/dev/null || true
        gsettings set org.mate.background picture-options 'zoom' 2>/dev/null || true
        gsettings set org.mate.interface gtk-theme "${THEME:-Adwaita}" 2>/dev/null || true
        gsettings set org.mate.interface icon-theme 'Adwaita' 2>/dev/null || true
        gsettings set org.mate.pluma style-scheme 'oblivion' 2>/dev/null || true
        gsettings set org.mate.sound event-sounds false 2>/dev/null || true
        ;;
    gnome)
        gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_PATH" 2>/dev/null || true
        gsettings set org.gnome.desktop.background picture-options 'zoom' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme "${THEME:-Adwaita}" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface enable-animations false 2>/dev/null || true
        ;;
    xfce)
        xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "$WALLPAPER_PATH" 2>/dev/null || true
        xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/image-style -s 5 2>/dev/null || true
        xfconf-query -c xsettings -p /Net/ThemeName -s "${THEME:-Adwaita}" 2>/dev/null || true
        xfconf-query -c xsettings -p /Net/IconThemeName -s 'Adwaita' 2>/dev/null || true
        ;;
    kde)
        kwriteconfig5 --file plasma-org.kde.plasma.desktop-appletsrc \
            --group 'Containments][1][Wallpaper][org.kde.image][General' \
            --key Image "file://$WALLPAPER_PATH" 2>/dev/null || true
        kwriteconfig5 --file kdeglobals --group General --key ColorScheme "${THEME:-Adwaita}" 2>/dev/null || true
        kwriteconfig5 --file kdeglobals --group KDE --key widgetStyle "${THEME:-Adwaita}" 2>/dev/null || true
        if command -v conky &>/dev/null; then
            killall conky 2>/dev/null || true
            conky -c /etc/seederlinux/conky/conky.conf &
        fi
        ;;
    lxde)
        mkdir -p "$USER_HOME/.config/pcmanfm/LXDE"
        if [ -f "$USER_HOME/.config/pcmanfm/LXDE/pcmanfm.conf" ]; then
            sed -i "s|wallpaper=.*|wallpaper=$WALLPAPER_PATH|" "$USER_HOME/.config/pcmanfm/LXDE/pcmanfm.conf" 2>/dev/null || true
        fi
        mkdir -p "$USER_HOME/.config/gtk-3.0"
        cat > "$USER_HOME/.config/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=${THEME:-Adwaita}
EOF
        ;;
esac

# ============================================================
# Iniciar Conky (Cinnamon e MATE)
# ============================================================
case "$DESKTOP_ENV" in
    cinnamon|mate)
        if [ -x /usr/local/bin/seederlinux-conky ]; then
            /usr/local/bin/seederlinux-conky &
        fi
        ;;
esac

echo "=== Logon concluido: $(date) - ${OM_ACRONYM} ==="
exit 0
PERMSCRIPT

chmod 755 /usr/local/bin/seederlinux-logon
echo ">>> Script permanente criado: /usr/local/bin/seederlinux-logon"

# ============================================================
# 2. Executar logica de logon AGORA (durante o bundle)
# ============================================================
echo ">>> Executando logica de logon (bundle)..."

USERNAME="${USER:-$(whoami)}"
USER_HOME="${HOME:-/home/$USERNAME}"

echo ">>> [logon] Usuario: $USERNAME"
echo ">>> [logon] Home: $USER_HOME"

mkdir -p "$USER_HOME/Desktop" "$USER_HOME/Downloads" "$USER_HOME/Documents"
mkdir -p "$USER_HOME/.config" "$USER_HOME/.local/share/applications"

if [ -n "$SERVIDOR_ARQUIVOS" ] && [ "$SERVIDOR_ARQUIVOS" != "" ]; then
    MOUNT_DIR="${MOUNT_BASE:-/mnt}"
    mkdir -p "$MOUNT_DIR"
    if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
        for SHARE in $COMPARTILHAMENTOS; do
            SHARE_MOUNT="${MOUNT_DIR}/${SHARE}"
            mkdir -p "$SHARE_MOUNT"
            mountpoint -q "$SHARE_MOUNT" 2>/dev/null || {
                mount -t cifs "//${SERVIDOR_ARQUIVOS}/${SHARE}" "$SHARE_MOUNT" \
                    -o "username=${USERNAME},domain=${DOMINIO_NETBIOS},uid=$(id -u),gid=$(id -g),iocharset=utf8,vers=3.0" 2>/dev/null || {
                    echo ">>> [logon] AVISO: Falha ao montar //${SERVIDOR_ARQUIVOS}/${SHARE}"
                }
            }
            echo ">>> [logon] Compartilhamento montado: ${SHARE}"
            cat > "$USER_HOME/Desktop/${SHARE}.desktop" <<EOF
[Desktop Entry]
Type=Link
Name=${SHARE}
URL=file://${SHARE_MOUNT}
Icon=folder
EOF
            chmod +x "$USER_HOME/Desktop/${SHARE}.desktop" 2>/dev/null || true
        done
    fi
fi

if [ -n "$DEFAULT_PRINTER" ] && [ "$DEFAULT_PRINTER" != "" ]; then
    lpoptions -d "$DEFAULT_PRINTER" 2>/dev/null || true
fi

if [ -n "$HOMEPAGE" ] && [ "$HOMEPAGE" != "" ]; then
    cat > "$USER_HOME/Desktop/Portal-${OM_ACRONYM}.desktop" <<EOF
[Desktop Entry]
Type=Link
Name=Portal ${OM_ACRONYM}
URL=${HOMEPAGE}
Icon=firefox-esr
EOF
    chmod +x "$USER_HOME/Desktop/Portal-${OM_ACRONYM}.desktop" 2>/dev/null || true
fi

chown -R "$USERNAME:$(id -gn)" "$USER_HOME" 2>/dev/null || true

echo ">>> [14] Logon concluido!"
echo "============================================================"
