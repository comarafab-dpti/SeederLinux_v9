#!/bin/bash
# ============================================================================
# Core Script: core_packages.sh
# SeederLinux Lite - Instalar pacotes essenciais
# ============================================================================
# Instala todos os pacotes necessarios para o funcionamento da estacao:
# ferramentas de rede, autenticacao, sistema grafico, utilitarios.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "03 - Instalar pacotes essenciais"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
DESKTOP_ENV="{{DESKTOP_ENV}}"
INSTALL_DESKTOP="{{INSTALL_DESKTOP}}"
SSH_PORT="{{SSH_PORT}}"
SSH_GROUPS="{{SSH_GROUPS}}"

echo ">>> Ambiente grafico solicitado (opcional): $DESKTOP_ENV"
echo ">>> Instalar ambiente grafico: $INSTALL_DESKTOP"
echo ">>> Porta SSH: ${SSH_PORT:-22}"
echo ">>> Grupos SSH: ${SSH_GROUPS:-nenhum}"

# ============================================================
# Detectar ambiente grafico ja instalado
# ============================================================
detectar_de() {
    if command -v cinnamon-session &>/dev/null; then echo "cinnamon"
    elif command -v mate-session &>/dev/null; then echo "mate"
    elif command -v gnome-session &>/dev/null; then echo "gnome"
    elif command -v startxfce4 &>/dev/null; then echo "xfce"
    elif command -v startplasma-x11 &>/dev/null; then echo "kde"
    elif command -v startlxde &>/dev/null; then echo "lxde"
    else echo "unknown"
    fi
}

detectar_dm() {
    if systemctl is-active --quiet lightdm 2>/dev/null; then echo "lightdm"
    elif systemctl is-active --quiet gdm3 2>/dev/null; then echo "gdm3"
    elif systemctl is-active --quiet sddm 2>/dev/null; then echo "sddm"
    elif [ -f /etc/X11/default-display-manager ]; then
        basename "$(cat /etc/X11/default-display-manager)"
    else echo "unknown"
    fi
}

DETECTED_DE="$(detectar_de)"
DETECTED_DM="$(detectar_dm)"
export DETECTED_DE DETECTED_DM

echo ">>> DE detectado na estacao: $DETECTED_DE"
echo ">>> DM detectado na estacao: $DETECTED_DM"

# ============================================================
# Atualizar sistema
# ============================================================
echo ">>> Atualizando pacotes do sistema..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade

# ============================================================
# Pacotes base do sistema
# ============================================================
echo ">>> Instalando pacotes base..."
BASE_PACKAGES=(
    wget
    curl
    gnupg
    ca-certificates
    lsb-release
    apt-transport-https
    software-properties-common
    unzip
    rsync
    htop
    vim
    nano
    less
    bash-completion
    net-tools
    dnsutils
    iproute2
    iputils-ping
    traceroute
    nmap
    tcpdump
    openssh-server
    openssh-client
    cifs-utils
    nfs-common
    smbclient
    policykit-1
    udisks2
    gvfs-backends
    gvfs-fuse
    fuse3
    libnotify-bin
    dbus-x11
    xdg-utils
    fonts-liberation
    fonts-noto
    fonts-noto-cjk
    fontconfig
)

apt-get install -y "${BASE_PACKAGES[@]}"

# ============================================================
# Pacotes de autenticacao (AD/Kerberos/SSSD)
# ============================================================
echo ">>> Instalando pacotes de autenticacao..."
AUTH_PACKAGES=(
    krb5-user
    samba
    samba-common
    samba-common-bin
    sssd
    sssd-tools
    sssd-krb5
    sssd-krb5-common
    libnss-sss
    libpam-sss
    adcli
    realmd
    oddjob
    oddjob-mkhomedir
    packagekit
    network-manager
    network-manager-gnome
)

apt-get install -y "${AUTH_PACKAGES[@]}"

# ============================================================
# Pacotes do ambiente grafico (OPCIONAL)
# ============================================================
# Por padrao NAO instala DE. Somente instala se INSTALL_DESKTOP=true
# e DESKTOP_ENV estiver definido. Caso contrario, usa o ambiente
# grafico ja presente na estacao (detectado em DETECTED_DE).
if [ "$INSTALL_DESKTOP" = "true" ] && [ -n "$DESKTOP_ENV" ] && [ "$DESKTOP_ENV" != "" ]; then
    echo ">>> Instalando ambiente grafico solicitado: $DESKTOP_ENV"
    case "$DESKTOP_ENV" in
        cinnamon)
            apt-get install -y cinnamon cinnamon-core lightdm
            ;;
        mate)
            apt-get install -y mate mate-core mate-desktop-environment lightdm
            ;;
        gnome)
            apt-get install -y gnome gnome-core gdm3
            ;;
        xfce)
            apt-get install -y xfce4 xfce4-goodies lightdm
            ;;
        kde)
            apt-get install -y kde-plasma-desktop sddm
            ;;
        lxde)
            apt-get install -y lxde lightdm
            ;;
        *)
            echo ">>> AVISO: Ambiente grafico nao reconhecido: $DESKTOP_ENV"
            echo ">>> Nenhum DE sera instalado. Usando o ja presente: $DETECTED_DE"
            ;;
    esac
else
    echo ">>> INSTALL_DESKTOP != true. Nao instalando DE."
    echo ">>> Utilizando ambiente grafico ja presente: $DETECTED_DE"
fi

# ============================================================
# Garantir repositorio universe (necessario para ocsinventory-agent no Mint/Ubuntu)
# ============================================================
echo ">>> Garantindo repositorio universe..."
if command -v add-apt-repository &>/dev/null; then
    add-apt-repository -y universe 2>/dev/null || true
fi
apt-get update -qq

# ============================================================
# Pacotes complementares
# ============================================================
echo ">>> Instalando pacotes complementares..."
EXTRA_PACKAGES=(
    cups
    cups-client
    system-config-printer
    x11vnc
    conky-all
    jq
    dmidecode
    openjdk-8-jre
    gimp
    vlc
    evince
    file-roller
    gparted
    gnome-screenshot
    xbacklight
    pavucontrol
    pulseaudio
    pulseaudio-utils
    alsa-utils
    intel-microcode
    amd64-microcode
    acpi
    acpid
    powermgmt-base
    upower
    colord
    geoclue-2.0
)

apt-get install -y "${EXTRA_PACKAGES[@]}" || true

# ============================================================
# OCS Inventory Agent (pacote critico para inventario)
# Instalado separadamente para garantir verificacao e diagnostico
# ============================================================
echo ">>> Instalando OCS Inventory Agent..."
if ! apt-get install -y ocsinventory-agent 2>/dev/null; then
    echo ">>> AVISO: Falha ao instalar ocsinventory-agent."
    echo ">>> Verifique se o repositorio universe esta habilitado."
    echo ">>> Comando manual: sudo add-apt-repository universe && sudo apt-get update && sudo apt-get install -y ocsinventory-agent"
else
    echo ">>> OCS Inventory Agent instalado com sucesso"
fi

# Firefox ESR com fallback para firefox
apt-get install -y firefox-esr firefox-esr-l10n-pt-br 2>/dev/null || \
    apt-get install -y firefox firefox-l10n-pt-br 2>/dev/null || true

# Firmware opcional (varia por distro)
apt-get install -y firmware-linux 2>/dev/null || true
apt-get install -y firmware-linux-nonfree 2>/dev/null || true

# ============================================================
# Limpar cache do APT
# ============================================================
echo ">>> Limpando cache do APT..."
apt-get clean
apt-get autoremove -y

# ============================================================
# Configurar porta SSH e AllowGroups
# ============================================================
if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "" ] && [ "$SSH_PORT" != "22" ]; then
    echo ">>> Configurando porta SSH: $SSH_PORT"
    if [ -f /etc/ssh/sshd_config ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true
        sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
        echo ">>> Porta SSH alterada para $SSH_PORT"
    fi
fi

if [ -n "$SSH_GROUPS" ] && [ "$SSH_GROUPS" != "" ]; then
    echo ">>> Configurando AllowGroups: $SSH_GROUPS"
    if [ -f /etc/ssh/sshd_config ]; then
        # Processar grupos (uma por linha ou separados por virgula)
        IFS=$'\n,' read -ra GRP_ARRAY <<< "$SSH_GROUPS"
        GRP_LIST=""
        for GRP in "${GRP_ARRAY[@]}"; do
            GRP=$(echo "$GRP" | xargs)
            if [ -n "$GRP" ] && [ "$GRP" != "" ]; then
                if [ -z "$GRP_LIST" ]; then
                    GRP_LIST="$GRP"
                else
                    GRP_LIST="$GRP_LIST $GRP"
                fi
            fi
        done
        if [ -n "$GRP_LIST" ]; then
            sed -i "s/^#*AllowGroups .*/AllowGroups $GRP_LIST/" /etc/ssh/sshd_config
            if ! grep -q "^AllowGroups " /etc/ssh/sshd_config; then
                echo "AllowGroups $GRP_LIST" >> /etc/ssh/sshd_config
            fi
            echo ">>> AllowGroups configurado: $GRP_LIST"
        fi
    fi
fi

# Reiniciar SSH se a porta ou grupos foram alterados
if [ -f /etc/ssh/sshd_config ]; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
fi

echo ">>> [03] Pacotes essenciais instalados!"
echo "============================================================"
