#!/bin/bash
# ============================================================================
# Core Script: core_branding.sh
# SeederLinux Lite - Wallpaper, logo, tema (varia por DE)
# ============================================================================
# Aplica identidade visual da OM: wallpaper, logo, tema GTK e configuracoes
# de aparencia. Varia conforme o ambiente grafico (DE).
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "13 - Aplicar identidade visual (branding)"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
OM_ACRONYM="{{OM_ACRONYM}}"
OM_NAME="{{OM_NAME}}"
DISPLAY_NAME="{{DISPLAY_NAME}}"
WALLPAPER_URL="{{WALLPAPER_URL}}"
WALLPAPER_LOGIN_URL="{{WALLPAPER_LOGIN_URL}}"
LOGO_URL="{{LOGO_URL}}"
GREETER_URL="{{GREETER_URL}}"
THEME="{{THEME}}"
DESKTOP_ENV="{{DESKTOP_ENV}}"
DISPLAY_MANAGER="{{DISPLAY_MANAGER}}"

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
fi
echo ">>> Ambiente detectado: $DESKTOP_ENV"

# ============================================================
# Detectar display manager se nao definido
# ============================================================
if [ -z "$DISPLAY_MANAGER" ] || [ "$DISPLAY_MANAGER" = "" ]; then
    if systemctl is-active --quiet lightdm 2>/dev/null; then DISPLAY_MANAGER="lightdm"
    elif systemctl is-active --quiet gdm3 2>/dev/null; then DISPLAY_MANAGER="gdm3"
    elif systemctl is-active --quiet sddm 2>/dev/null; then DISPLAY_MANAGER="sddm"
    elif [ -f /etc/X11/default-display-manager ]; then
        DISPLAY_MANAGER="$(basename "$(cat /etc/X11/default-display-manager)")"
    else DISPLAY_MANAGER="unknown"
    fi
fi
echo ">>> Display Manager detectado: $DISPLAY_MANAGER"

echo ">>> OM: $OM_ACRONYM - $OM_NAME"
echo ">>> Ambiente: $DESKTOP_ENV / $DISPLAY_MANAGER"
echo ">>> Tema: $THEME"

# ============================================================
# Criar diretorios de branding
# ============================================================
mkdir -p /usr/share/seederlinux/branding
mkdir -p /usr/share/backgrounds/seederlinux
mkdir -p /usr/share/pixmaps

# ============================================================
# Baixar e instalar wallpaper
# ============================================================
echo ">>> Baixando wallpaper..."
if [ -n "$WALLPAPER_URL" ] && [ "$WALLPAPER_URL" != "" ]; then
    if wget -q -O /usr/share/backgrounds/seederlinux/wallpaper.jpg "$WALLPAPER_URL"; then
        echo ">>> Wallpaper instalado"
    else
        echo ">>> AVISO: Falha ao baixar wallpaper de: $WALLPAPER_URL"
    fi
else
    echo ">>> WALLPAPER_URL nao definido. Pulando wallpaper."
fi

# ============================================================
# Baixar e instalar wallpaper de login
# ============================================================
echo ">>> Baixando wallpaper de login..."
if [ -n "$WALLPAPER_LOGIN_URL" ] && [ "$WALLPAPER_LOGIN_URL" != "" ]; then
    if wget -q -O /usr/share/backgrounds/seederlinux/wallpaper-login.jpg "$WALLPAPER_LOGIN_URL"; then
        echo ">>> Wallpaper de login instalado"
    else
        echo ">>> AVISO: Falha ao baixar wallpaper de login"
    fi
fi

# ============================================================
# Baixar e instalar logo
# ============================================================
echo ">>> Baixando logo..."
if [ -n "$LOGO_URL" ] && [ "$LOGO_URL" != "" ]; then
    if wget -q -O /usr/share/pixmaps/seederlinux-logo.png "$LOGO_URL"; then
        echo ">>> Logo instalado"
    else
        echo ">>> AVISO: Falha ao baixar logo"
    fi
fi

# ============================================================
# Baixar e instalar greeter personalizado
# ============================================================
echo ">>> Baixando greeter..."
if [ -n "$GREETER_URL" ] && [ "$GREETER_URL" != "" ]; then
    GREETER_TARBALL="/tmp/seederlinux-greeter.tar.gz"
    if wget -q -O "$GREETER_TARBALL" "$GREETER_URL"; then
        mkdir -p /tmp/seederlinux-greeter
        tar xzf "$GREETER_TARBALL" -C /tmp/seederlinux-greeter
        # Copiar para o local apropriado conforme o DM
        case "$DISPLAY_MANAGER" in
            lightdm)
                cp -r /tmp/seederlinux-greeter/* /usr/share/lightdm/ 2>/dev/null || true
                ;;
            gdm3)
                cp -r /tmp/seederlinux-greeter/* /usr/share/gdm/ 2>/dev/null || true
                ;;
            sddm)
                cp -r /tmp/seederlinux-greeter/* /usr/share/sddm/themes/ 2>/dev/null || true
                ;;
        esac
        rm -rf /tmp/seederlinux-greeter "$GREETER_TARBALL"
        echo ">>> Greeter instalado"
    else
        echo ">>> AVISO: Falha ao baixar greeter"
    fi
fi

# ============================================================
# Aplicar tema GTK
# ============================================================
echo ">>> Aplicando tema GTK: $THEME"
if [ -n "$THEME" ] && [ "$THEME" != "" ]; then
    # Configuracao global do tema
    mkdir -p /etc/skel/.config/gtk-3.0
    cat > /etc/skel/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-theme-name=${THEME}
gtk-icon-theme-name=Adwaita
gtk-font-name=DejaVu Sans 10
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=16
gtk-toolbar-style=GTK_TOOLBAR_BOTH
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-application-prefer-dark-theme=0
EOF
    echo ">>> Tema GTK configurado: $THEME"
fi

# ============================================================
# Aplicar wallpaper e configuracoes conforme o DE
# ============================================================
echo ">>> Aplicando configuracoes para: $DESKTOP_ENV"

case "$DESKTOP_ENV" in
    cinnamon)
        # Cinnamon - via gsettings (schema global)
        mkdir -p /etc/skel/.config
        cat > /etc/skel/.config/cinnamon-settings.conf <<EOF
[org.cinnamon.desktop.background]
picture-uri='file:///usr/share/backgrounds/seederlinux/wallpaper.jpg'
picture-options='zoom'

[org.cinnamon.desktop.interface]
gtk-theme='${THEME}'
icon-theme='Adwaita'

[org.cinnamon.theme]
name='${THEME}'
EOF
        ;;

    mate)
        # MATE - via gsettings
        mkdir -p /etc/skel/.config
        cat > /etc/skel/.config/mate-background.conf <<EOF
[org.mate.desktop.background]
picture-filename='/usr/share/backgrounds/seederlinux/wallpaper.jpg'
picture-options='zoom'

[org.mate.desktop.interface]
gtk-theme='${THEME}'
icon-theme='Adwaita'
EOF
        ;;

    gnome)
        # GNOME - via gsettings (dconf)
        mkdir -p /etc/dconf/db/local.d
        cat > /etc/dconf/db/local.d/seederlinux-branding <<EOF
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/seederlinux/wallpaper.jpg'
picture-uri-dark='file:///usr/share/backgrounds/seederlinux/wallpaper.jpg'
picture-options='zoom'

[org/gnome/desktop/interface]
gtk-theme='${THEME}'
icon-theme='Adwaita'

[org/gnome/login-screen]
logo='/usr/share/pixmaps/seederlinux-logo.png'
EOF
        dconf update 2>/dev/null || true
        ;;

    xfce)
        # XFCE - via xfconf
        mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
        cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/seederlinux/wallpaper.jpg"/>
        <property name="image-style" type="int" value="5"/>
      </property>
    </property>
  </property>
</channel>
EOF
        ;;

    kde)
        # KDE Plasma - via kdeglobals
        mkdir -p /etc/skel/.config
        cat > /etc/skel/.config/kdeglobals <<EOF
[General]
ColorScheme=${THEME}
Name=${THEME}

[KDE]
widgetStyle=${THEME}
EOF
        # Wallpaper via plasma config
        mkdir -p /etc/skel/.config
        cat > /etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc <<EOF
[Containments][1][Wallpaper][org.kde.image][General]
Image=file:///usr/share/backgrounds/seederlinux/wallpaper.jpg
EOF
        ;;

    lxde)
        # LXDE - via pcmanfm
        mkdir -p /etc/skel/.config/pcmanfm/LXDE
        cat > /etc/skel/.config/pcmanfm/LXDE/pcmanfm.conf <<EOF
[desktop]
wallpaper_mode=crop
wallpaper=/usr/share/backgrounds/seederlinux/wallpaper.jpg
EOF
        ;;
esac

# ============================================================
# Configurar wallpaper de login (greeter)
# ============================================================
echo ">>> Configurando wallpaper de login..."
case "$DISPLAY_MANAGER" in
    lightdm)
        mkdir -p /etc/lightdm
        if [ -f /usr/share/backgrounds/seederlinux/wallpaper-login.jpg ]; then
            cat > /etc/lightdm/lightdm-gtk-greeter.conf <<EOF
[greeter]
background=/usr/share/backgrounds/seederlinux/wallpaper-login.jpg
logo=/usr/share/pixmaps/seederlinux-logo.png
theme-name=${THEME}
icon-theme-name=Adwaita
font-name=DejaVu Sans 10
EOF
        fi
        ;;
    gdm3)
        if [ -f /usr/share/backgrounds/seederlinux/wallpaper-login.jpg ]; then
            # GDM3 usa dconf para configuracao
            mkdir -p /etc/dconf/db/gdm.d
            cat > /etc/dconf/db/gdm.d/01-seederlinux-background <<EOF
[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/seederlinux/wallpaper-login.jpg'
picture-options='zoom'
EOF
            dconf update 2>/dev/null || true
        fi
        ;;
    sddm)
        if [ -f /usr/share/backgrounds/seederlinux/wallpaper-login.jpg ]; then
            mkdir -p /etc/sddm.conf.d
            cat > /etc/sddm.conf.d/seederlinux.conf <<EOF
[Theme]
ThemeDir=/usr/share/sddm/themes
Current=seederlinux
Background=/usr/share/backgrounds/seederlinux/wallpaper-login.jpg
EOF
        fi
        ;;
esac

echo ">>> [13] Identidade visual aplicada!"
echo "============================================================"
