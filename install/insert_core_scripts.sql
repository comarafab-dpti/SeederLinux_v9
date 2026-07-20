-- ============================================================================
-- SeederLinux Lite - Insercao dos Scripts Core
-- ============================================================================
-- Este arquivo popula a tabela 'scripts' com todos os scripts Core.
-- Gerado automaticamente a partir dos arquivos em scripts/core/.
--
-- ESCAPING: Usa dollar-quoting do PostgreSQL ($SeederScript$) para o conteudo
-- dos scripts, eliminando problemas com aspas simples, aspas duplas,
-- backslashes e qualquer outro caractere especial no bash.
-- ============================================================================

-- Limpar scripts core existentes (opcional - descomente se necessario)
-- DELETE FROM scripts WHERE is_core = TRUE;


-- ============================================================================
-- Configuracao de DNS (ordem 1) - core_dns.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracao de DNS',
    'core_dns.sh',
    'Configura DNS temporario, NTP e /etc/hosts. Roda ANTES de repositorios para permitir apt-get update.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_dns.sh
# SeederLinux Lite - DNS, NTP e resolucao de nomes
# ============================================================================
# Configura DNS temporario para permitir resolucao durante o provisionamento,
# ajusta /etc/resolv.conf, /etc/hosts e sincroniza NTP.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "01 - Configurar DNS, NTP e resolucao de nomes"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
DOMINIO="{{DOMINIO}}"
DC_IP="{{DC_IP}}"
DC_IP_LIST="{{DC_IP_LIST}}"
DNS_PRIMARIO="{{DNS_PRIMARIO}}"
DNS_SECUNDARIO="{{DNS_SECUNDARIO}}"
DNS_INTERNET="{{DNS_INTERNET}}"
NTP_SERVER="{{NTP_SERVER}}"
OM_ACRONYM="{{OM_ACRONYM}}"

echo ">>> Dominio: $DOMINIO"
echo ">>> DNS primario: $DNS_PRIMARIO"
echo ">>> DNS secundario: ${DNS_SECUNDARIO}"
echo ">>> NTP: $NTP_SERVER"

# ============================================================
# Hostname interativo
# ============================================================
CURRENT_HOSTNAME=$(hostname)
echo ">>> Hostname atual: $CURRENT_HOSTNAME"
read -p ">>> Deseja alterar o hostname? (s/N): " CHANGE_HOST
if [[ "$CHANGE_HOST" =~ ^[Ss]$ ]]; then
    read -p ">>> Novo hostname: " NEW_HOSTNAME
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo ">>> Hostname alterado para: $NEW_HOSTNAME"
fi

HOSTNAME_SHORT=$(hostname | cut -d. -f1)
HOSTNAME_FQDN="${HOSTNAME_SHORT}.${DOMINIO}"

# ============================================================
# DNS temporário (para permitir apt-get durante o provisionamento)
# ============================================================
echo ">>> Configurando DNS temporario (internet primeiro para baixar pacotes)..."
echo "nameserver $DNS_INTERNET" > /etc/resolv.conf
if [ -n "$DNS_PRIMARIO" ] && [ "$DNS_PRIMARIO" != "" ]; then
    echo "nameserver $DNS_PRIMARIO" >> /etc/resolv.conf
fi
if [ -n "$DNS_SECUNDARIO" ] && [ "$DNS_SECUNDARIO" != "" ]; then
    echo "nameserver $DNS_SECUNDARIO" >> /etc/resolv.conf
fi
echo "search $DOMINIO" >> /etc/resolv.conf
echo ">>> DNS temporario configurado"

# ============================================================
# /etc/hosts - garantir resolucao do proprio host e do dominio
# ============================================================
echo ">>> Configurando /etc/hosts..."

cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

cat > /etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   ${HOSTNAME_FQDN} ${HOSTNAME_SHORT}

# Controladores de dominio
EOF

# Adiciona todos os DCs no /etc/hosts
DC_HOSTNAME="dc-${OM_ACRONYM,,}"
for DC in $DC_IP_LIST; do
    echo "$DC    ${DC_HOSTNAME}.${DOMINIO} ${DC_HOSTNAME}" >> /etc/hosts
done

echo ">>> /etc/hosts configurado"

# ============================================================
# NTP - sincronizar horario com o servidor
# ============================================================
echo ">>> Configurando NTP..."
if command -v timedatectl &> /dev/null; then
    timedatectl set-ntp true 2>/dev/null || true
fi

if [ -n "$NTP_SERVER" ] && [ "$NTP_SERVER" != "" ]; then
    # Tenta sincronizar imediatamente
    if command -v ntpdate &> /dev/null; then
        ntpdate "$NTP_SERVER" 2>/dev/null || true
    elif command -v chronyc &> /dev/null; then
        chronyc -a makestep 2>/dev/null || true
    fi

    # Configura NTP permanente
    if [ -d /etc/chrony ]; then
        cat > /etc/chrony/chrony.conf <<EOF
server $NTP_SERVER iburst
driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
EOF
        systemctl restart chrony 2>/dev/null || true
    elif [ -f /etc/ntp.conf ]; then
        cp /etc/ntp.conf /etc/ntp.conf.bak 2>/dev/null || true
        cat > /etc/ntp.conf <<EOF
server $NTP_SERVER iburst
driftfile /var/lib/ntp/ntp.drift
restrict default kod nomodify notrap nopeer noquery
restrict 127.0.0.1
EOF
        systemctl restart ntp 2>/dev/null || true
    fi
    echo ">>> NTP configurado: $NTP_SERVER"
else
    echo ">>> NTP_SERVER nao definido, usando padrao do sistema"
fi

echo ">>> [01] DNS, NTP e resolucao de nomes configurados!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    1,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Configuracao de Repositorios (ordem 2) - core_repositories.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracao de Repositorios',
    'core_repositories.sh',
    'Configura repositorios APT (oficial, espelho ou customizado) apos o DNS estar resolvendo.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_repositories.sh
# SeederLinux Lite - Configurar sources.list (APT)
# ============================================================================
# Detecta a distribuicao (Debian, Ubuntu, Mint, Zorin) e configura os
# repositorios APT conforme o modo e as variaveis por distro:
#   REPOSITORY_DEBIAN_ENABLED / REPOSITORY_DEBIAN_URL
#   REPOSITORY_UBUNTU_ENABLED / REPOSITORY_UBUNTU_URL
#   REPOSITORY_MINT_ENABLED   / REPOSITORY_MINT_URL
#   REPOSITORY_ZORIN_ENABLED  / REPOSITORY_ZORIN_URL
# NUNCA altera sources.list se o modo for PUBLIC ou se o mirror da distro
# detectada nao estiver habilitado.
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "02 - Configurar repositorios APT"
echo "============================================================"

# ============================================================
# Variaveis globais
# ============================================================
REPOSITORY_MODE="{{REPOSITORY_MODE}}"
REPOSITORY_URL="{{REPOSITORY_URL}}"
REPOSITORY_FALLBACK="{{REPOSITORY_FALLBACK}}"

# Variaveis por distro
REPOSITORY_DEBIAN_ENABLED="{{REPOSITORY_DEBIAN_ENABLED}}"
REPOSITORY_DEBIAN_URL="{{REPOSITORY_DEBIAN_URL}}"
REPOSITORY_UBUNTU_ENABLED="{{REPOSITORY_UBUNTU_ENABLED}}"
REPOSITORY_UBUNTU_URL="{{REPOSITORY_UBUNTU_URL}}"
REPOSITORY_MINT_ENABLED="{{REPOSITORY_MINT_ENABLED}}"
REPOSITORY_MINT_URL="{{REPOSITORY_MINT_URL}}"
REPOSITORY_ZORIN_ENABLED="{{REPOSITORY_ZORIN_ENABLED}}"
REPOSITORY_ZORIN_URL="{{REPOSITORY_ZORIN_URL}}"

echo ">>> Modo de repositorio: $REPOSITORY_MODE"

# ============================================================
# Detectar a distribuicao
# ============================================================
detect_distro() {
    if [ -f /etc/linuxmint/info ]; then
        echo "mint"
    elif [ -f /etc/zorin-release ]; then
        echo "zorin"
    elif grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        echo "ubuntu"
    elif grep -qi "debian" /etc/os-release 2>/dev/null; then
        echo "debian"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)
echo ">>> Distribuicao detectada: $DISTRO"

# ============================================================
# Backup do sources.list original
# ============================================================
backup_sources() {
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%Y%m%d%H%M%S)
        echo ">>> Backup do sources.list criado"
    fi
}

# ============================================================
# Obter codename da distro
# ============================================================
get_codename() {
    lsb_release -cs 2>/dev/null || echo "$1"
}

# ============================================================
# Configuracao conforme o modo
# ============================================================
case "$REPOSITORY_MODE" in
    PUBLIC|"")
        echo ">>> Modo PUBLIC: mantendo repositorios padrao da distribuicao ($DISTRO)."
        echo ">>> Nenhuma alteracao em sources.list foi feita."
        ;;

    MIRROR|HYBRID)
        case "$DISTRO" in
            debian)
                if [ "${REPOSITORY_DEBIAN_ENABLED:-false}" = "true" ] && [ -n "${REPOSITORY_DEBIAN_URL:-}" ]; then
                    echo ">>> Configurando mirror Debian: $REPOSITORY_DEBIAN_URL"
                    backup_sources
                    DEBIAN_CODENAME=$(get_codename trixie)
                    cat > /etc/apt/sources.list <<EOF
deb $REPOSITORY_DEBIAN_URL/debian $DEBIAN_CODENAME main contrib non-free non-free-firmware
deb $REPOSITORY_DEBIAN_URL/debian-security $DEBIAN_CODENAME-security main contrib non-free non-free-firmware
deb $REPOSITORY_DEBIAN_URL/debian $DEBIAN_CODENAME-updates main contrib non-free non-free-firmware
EOF
                    if [ "$REPOSITORY_MODE" = "HYBRID" ] && [ -n "$REPOSITORY_FALLBACK" ]; then
                        echo ">>> Adicionando fallback Debian..."
                        cat >> /etc/apt/sources.list <<EOF
deb $REPOSITORY_FALLBACK/debian $DEBIAN_CODENAME main contrib non-free non-free-firmware
deb $REPOSITORY_FALLBACK/debian-security $DEBIAN_CODENAME-security main contrib non-free non-free-firmware
deb $REPOSITORY_FALLBACK/debian $DEBIAN_CODENAME-updates main contrib non-free non-free-firmware
EOF
                    fi
                else
                    echo ">>> Mirror Debian nao habilitado. Mantendo repositorios oficiais."
                fi
                ;;

            ubuntu)
                if [ "${REPOSITORY_UBUNTU_ENABLED:-false}" = "true" ] && [ -n "${REPOSITORY_UBUNTU_URL:-}" ]; then
                    echo ">>> Configurando mirror Ubuntu: $REPOSITORY_UBUNTU_URL"
                    backup_sources
                    UBUNTU_CODENAME=$(get_codename noble)
                    cat > /etc/apt/sources.list <<EOF
deb $REPOSITORY_UBUNTU_URL/ubuntu $UBUNTU_CODENAME main restricted universe multiverse
deb $REPOSITORY_UBUNTU_URL/ubuntu $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $REPOSITORY_UBUNTU_URL/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                    if [ "$REPOSITORY_MODE" = "HYBRID" ] && [ -n "$REPOSITORY_FALLBACK" ]; then
                        echo ">>> Adicionando fallback Ubuntu..."
                        cat >> /etc/apt/sources.list <<EOF
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME main restricted universe multiverse
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                    fi
                else
                    echo ">>> Mirror Ubuntu nao habilitado. Mantendo repositorios oficiais."
                fi
                ;;

            mint)
                MINT_CODENAME=$(get_codename wilma)
                UBUNTU_CODENAME=$(grep UBUNTU_CODENAME /etc/linuxmint/info 2>/dev/null | cut -d= -f2 || echo noble)
                MINT_OK=false

                if [ "${REPOSITORY_MINT_ENABLED:-false}" = "true" ] && [ -n "${REPOSITORY_MINT_URL:-}" ]; then
                    MINT_OK=true
                fi

                if [ "$MINT_OK" = "true" ]; then
                    echo ">>> Configurando mirror Mint: $REPOSITORY_MINT_URL"
                    backup_sources
                    cat > /etc/apt/sources.list <<EOF
deb $REPOSITORY_MINT_URL/mint $MINT_CODENAME main upstream import backport
EOF
                    if [ "${REPOSITORY_UBUNTU_ENABLED:-false}" = "true" ] && [ -n "${REPOSITORY_UBUNTU_URL:-}" ]; then
                        echo ">>> Configurando mirror Ubuntu base para Mint: $REPOSITORY_UBUNTU_URL"
                        cat >> /etc/apt/sources.list <<EOF
deb $REPOSITORY_UBUNTU_URL/ubuntu $UBUNTU_CODENAME main restricted universe multiverse
deb $REPOSITORY_UBUNTU_URL/ubuntu $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $REPOSITORY_UBUNTU_URL/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                    else
                        echo ">>> Mirror Ubuntu nao habilitado. Mantendo repositorios oficiais do Ubuntu base."
                        cat >> /etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu $UBUNTU_CODENAME main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $UBUNTU_CODENAME-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                    fi

                    if [ "$REPOSITORY_MODE" = "HYBRID" ] && [ -n "$REPOSITORY_FALLBACK" ]; then
                        echo ">>> Adicionando fallback..."
                        cat >> /etc/apt/sources.list <<EOF
deb $REPOSITORY_FALLBACK/mint $MINT_CODENAME main upstream import backport
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME main restricted universe multiverse
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                    fi
                else
                    echo ">>> Mirror Mint nao habilitado. Mantendo repositorios oficiais."
                fi
                ;;

            zorin)
                if [ "${REPOSITORY_ZORIN_ENABLED:-false}" = "true" ] && [ -n "${REPOSITORY_ZORIN_URL:-}" ]; then
                    echo ">>> Configurando mirror Zorin: $REPOSITORY_ZORIN_URL"
                    backup_sources
                    UBUNTU_CODENAME=$(get_codename jammy)
                    cat > /etc/apt/sources.list <<EOF
deb $REPOSITORY_ZORIN_URL/ubuntu $UBUNTU_CODENAME main restricted universe multiverse
deb $REPOSITORY_ZORIN_URL/ubuntu $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $REPOSITORY_ZORIN_URL/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                    if [ "$REPOSITORY_MODE" = "HYBRID" ] && [ -n "$REPOSITORY_FALLBACK" ]; then
                        echo ">>> Adicionando fallback Zorin..."
                        cat >> /etc/apt/sources.list <<EOF
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME main restricted universe multiverse
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME-updates main restricted universe multiverse
deb $REPOSITORY_FALLBACK/ubuntu $UBUNTU_CODENAME-security main restricted universe multiverse
EOF
                    fi
                else
                    echo ">>> Mirror Zorin nao habilitado. Mantendo repositorios oficiais."
                fi
                ;;

            *)
                echo ">>> Distribuicao nao reconhecida. Mantendo sources.list padrao."
                ;;
        esac
        ;;

    CUSTOM)
        if [ -z "$REPOSITORY_URL" ] || [ "$REPOSITORY_URL" = "" ]; then
            echo ">>> ERRO: REPOSITORY_URL nao definido para modo CUSTOM"
            read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
            if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
                echo ">>> Instalacao abortada pelo usuario."
                exit 1
            fi
            echo ">>> Continuando apesar do erro..."
        fi

        echo ">>> Configurando repositorio personalizado"
        backup_sources

        cat > /etc/apt/sources.list <<EOF
$REPOSITORY_URL
EOF
        ;;

    *)
        echo ">>> ERRO: Modo de repositorio invalido: $REPOSITORY_MODE"
        read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
        if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
            echo ">>> Instalacao abortada pelo usuario."
            exit 1
        fi
        echo ">>> Continuando apesar do erro..."
        ;;
esac

# ============================================================
# Atualizar indice de pacotes
# ============================================================
echo ">>> Atualizando apt-get update..."
apt-get update

echo ">>> [02] Repositorios configurados com sucesso!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    2,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Instalacao de Pacotes (ordem 3) - core_packages.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Instalacao de Pacotes',
    'core_packages.sh',
    'Instala TODOS os pacotes necessarios (sistema, OCS, CUPS, VNC, Conky, Java, etc).',
    $SeederScript$#!/bin/bash
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
$SeederScript$,
    TRUE,
    TRUE,
    3,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Ingresso em Dominio AD (ordem 4) - core_domain.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Ingresso em Dominio AD',
    'core_domain.sh',
    'Ingressa a estacao no Active Directory (SSSD/Winbind com fallback).',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_domain.sh
# SeederLinux Lite - Ingresso no AD (SSSD/Winbind com fallback)
# ============================================================================
# Configura Kerberos, Samba, SSSD, PAM, NSS, sudo e mkhomedir para
# ingressar a estacao no dominio Active Directory.
#
# Suporta AUTH_METHOD:
#   sssd    - Apenas SSSD (realm join)
#   winbind - Apenas Winbind (net ads join)
#   both    - SSSD primeiro, fallback para Winbind se falhar
#
# Suporta ADMIN_PASSWORD_B64 (senha codificada em base64).
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "04 - Ingresso no Active Directory"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
DC_IP="{{DC_IP}}"
DC_IP_LIST="{{DC_IP_LIST}}"
OU_PADRAO="{{OU_PADRAO}}"
GRUPO_ADMIN="{{GRUPO_ADMIN}}"
GRUPO_ADMIN_AD="{{GRUPO_ADMIN_AD}}"
GRUPO_ADMIN_LINUX="{{GRUPO_ADMIN_LINUX}}"
GRUPO_DASTI="{{GRUPO_DASTI}}"
OFFLINE_AUTH_ENABLED="{{OFFLINE_AUTH_ENABLED}}"
OFFLINE_AUTH_DAYS="{{OFFLINE_AUTH_DAYS}}"
ADMIN_USERNAME="{{ADMIN_USERNAME}}"
AUTH_METHOD="{{AUTH_METHOD}}"
ADMIN_PASSWORD_B64="__ADMIN_PASSWORD_B64__"

echo ">>> Dominio: $DOMINIO"
echo ">>> NetBIOS: $DOMINIO_NETBIOS}"
echo ">>> DC principal: $DC_IP"
echo ">>> Metodo de autenticacao: $AUTH_METHOD"

# ============================================================
# Decodificar senha base64 se fornecida
# ============================================================
if [ -n "$ADMIN_PASSWORD_B64" ] && [ "$ADMIN_PASSWORD_B64" != "" ]; then
    ADMIN_PASSWORD=$(echo "$ADMIN_PASSWORD_B64" | base64 -d 2>/dev/null)
    if [ -n "$ADMIN_PASSWORD" ]; then
        echo ">>> Senha do AD decodificada de base64 (${#ADMIN_PASSWORD} caracteres)"
    else
        echo ">>> AVISO: Falha ao decodificar ADMIN_PASSWORD_B64 — senha nao decodificada"
    fi
fi

# ============================================================
# Ajustar DNS para ingresso no dominio
# ============================================================
echo ">>> Ajustando DNS para ingresso no dominio..."

cp /etc/resolv.conf /etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null || true

cat > /etc/resolv.conf <<EOF
nameserver $DNS_PRIMARIO
EOF

if [ -n "$DNS_SECUNDARIO" ] && [ "$DNS_SECUNDARIO" != "" ]; then
    echo "nameserver $DNS_SECUNDARIO" >> /etc/resolv.conf
fi

echo "search $DOMINIO" >> /etc/resolv.conf

echo ">>> DNS ajustado para ingresso: $DNS_PRIMARIO"

echo ">>> Verificando resolucao do dominio..."
if ! host "$DOMINIO" > /dev/null 2>&1; then
    echo ">>> AVISO: Dominio $DOMINIO nao resolve. Verifique o DNS."
    echo ">>> Tentando mesmo assim..."
fi

# ============================================================
# Definir modo winbind offline logon conforme AUTH_METHOD e OFFLINE_AUTH_ENABLED
# ============================================================
if { [ "$AUTH_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "both" ]; } && [ "$OFFLINE_AUTH_ENABLED" = "true" ]; then
    WINBIND_OFFLINE="yes"
else
    WINBIND_OFFLINE="false"
fi

# ============================================================
# Configurar Kerberos
# ============================================================
echo ">>> Configurando Kerberos..."
REALM="${DOMINIO^^}"

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = true
    rdns = false
    ticket_lifetime = 24h
    forwardable = yes
    renew_lifetime = 7d

[realms]
    ${REALM} = {
        kdc = ${DC_IP}
        admin_server = ${DC_IP}
    }

[domain_realm]
    .${DOMINIO} = ${REALM}
    ${DOMINIO} = ${REALM}
EOF

echo ">>> Kerberos configurado"

# ============================================================
# Configurar Samba
# ============================================================
echo ">>> Configurando Samba..."
cat > /etc/samba/smb.conf <<EOF
[global]
    workgroup = ${DOMINIO_NETBIOS}
    realm = ${DOMINIO}
    security = ads
    dns forwarder = ${DC_IP}
    idmap config * : backend = tdb
    idmap config * : range = 3000-7999
    idmap config ${DOMINIO_NETBIOS} : backend = rid
    idmap config ${DOMINIO_NETBIOS} : range = 10000-999999
    template shell = /bin/bash
    template homedir = /home/%D/%U
    winbind use default domain = true
    winbind offline logon = ${WINBIND_OFFLINE}
    winbind nss info = rfc2307
    winbind enum users = no
    winbind enum groups = no
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes
EOF

echo ">>> Samba configurado"

# ============================================================
# Obter credenciais do administrador do dominio
# ============================================================
echo "============================================================"
echo ">>> INGRESSO NO DOMINIO - CREDENCIAIS NECESSARIAS"
echo "============================================================"

if [ -z "$ADMIN_USERNAME" ] || [ "$ADMIN_USERNAME" = "Administrator" ]; then
    read -p ">>> Usuario administrador do dominio [Administrator]: " ADMIN_USER
    ADMIN_USERNAME="${ADMIN_USER:-Administrator}"
fi

# Se a senha nao foi decodificada de base64, pedir interativamente
if [ -z "$ADMIN_PASSWORD" ] || [ "$ADMIN_PASSWORD" = "" ]; then
    read -s -p ">>> Senha do administrador do dominio: " ADMIN_PASSWORD
    echo ""
fi

echo ">>> Ingressando no dominio..."

# ============================================================
# Obter ticket Kerberos - tentar multiplas combinacoes
# ============================================================
echo ">>> Obtendo ticket Kerberos..."
KINIT_OK=false

# Tentativa 1: REALM maiusculo (Administrator@COMARA.INTRAER)
echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME}@${DOMINIO^^}" 2>/dev/null && KINIT_OK=true

# Tentativa 2: NETBIOS (Administrator@COMARA)
[ "$KINIT_OK" != "true" ] && echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME}@${DOMINIO_NETBIOS}" 2>/dev/null && KINIT_OK=true

# Tentativa 3: Dominio minusculo (administrator@comara.intraer)
[ "$KINIT_OK" != "true" ] && echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME,,}@${DOMINIO,,}" 2>/dev/null && KINIT_OK=true

# Tentativa 4: Usuario minusculo, REALM maiusculo (administrator@COMARA.INTRAER)
[ "$KINIT_OK" != "true" ] && echo "$ADMIN_PASSWORD" | kinit "${ADMIN_USERNAME,,}@${DOMINIO^^}" 2>/dev/null && KINIT_OK=true

if [ "$KINIT_OK" != "true" ]; then
    echo ">>> ERRO: Falha ao obter ticket Kerberos com todas as combinacoes."
    echo ">>> Verifique usuario/senha e conectividade com o DC."
    read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo ">>> Instalacao abortada pelo usuario."
        exit 1
    fi
    echo ">>> Continuando apesar do erro..."
else
    echo ">>> Ticket Kerberos obtido com sucesso!"
fi

# ============================================================
# Ingressar no dominio - SSSD (realm join) e/ou Winbind (net ads join)
# ============================================================
JOIN_OK=false
JOIN_METHOD=""

# --- Metodo 1: SSSD (realm join) ---
if [ "$AUTH_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "both" ]; then
    echo ">>> Ingressando no dominio via realm join (SSSD)..."
    if echo "$ADMIN_PASSWORD" | realm join "$DOMINIO" \
        --user="$ADMIN_USERNAME" \
        --computer-ou="$OU_PADRAO" \
        --verbose 2>&1; then

        # Verificar se o keytab foi gerado
        if [ ! -f /etc/krb5.keytab ]; then
            echo ">>> Keytab nao encontrado. Tentando gerar com adcli..."
            echo "$ADMIN_PASSWORD" | adcli join "$DOMINIO" \
                --login-user="$ADMIN_USERNAME" \
                --domain-ou="$OU_PADRAO" \
                --verbose 2>&1 || true
        fi

        if [ -f /etc/krb5.keytab ]; then
            JOIN_OK=true
            JOIN_METHOD="sssd"
            echo ">>> Ingresso via SSSD (realm join) bem-sucedido!"
        else
            echo ">>> AVISO: realm join executado mas keytab nao gerado."
        fi
    else
        echo ">>> AVISO: realm join falhou."
    fi
fi

# --- Metodo 2: Winbind (net ads join) - fallback ou metodo principal ---
if [ "$JOIN_OK" != "true" ]; then
    if [ "$AUTH_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "both" ]; then
        echo ">>> Ingressando no dominio via net ads join (Winbind)..."
        if echo "$ADMIN_PASSWORD" | net ads join "$DOMINIO" \
            -U "$ADMIN_USERNAME" \
            createcomputer="$OU_PADRAO" 2>&1; then

            if [ -f /etc/krb5.keytab ]; then
                JOIN_OK=true
                JOIN_METHOD="winbind"
                echo ">>> Ingresso via Winbind (net ads join) bem-sucedido!"
            else
                echo ">>> AVISO: net ads join executado mas keytab nao gerado."
                # Tentar gerar keytab manualmente
                net ads keytab create -U "$ADMIN_USERNAME" 2>/dev/null && {
                    JOIN_OK=true
                    JOIN_METHOD="winbind"
                    echo ">>> Keytab gerado manualmente via net ads keytab."
                } || true
            fi
        else
            echo ">>> AVISO: net ads join falhou."
        fi
    fi
fi

# --- Verificar resultado do ingresso ---
if [ "$JOIN_OK" = "false" ]; then
    echo ">>> ERRO: Falha ao ingressar no dominio com todos os metodos."
    read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo ">>> Instalacao abortada pelo usuario."
        exit 1
    fi
    echo ">>> Continuando apesar do erro..."
fi

# Verificar keytab
if [ -f /etc/krb5.keytab ]; then
    echo ">>> Keytab gerado com sucesso."
    chmod 600 /etc/krb5.keytab
fi

echo ">>> Metodo de ingresso utilizado: ${JOIN_METHOD:-nenhum}"
unset ADMIN_PASSWORD
unset ADMIN_PASSWORD_B64
echo ">>> Ingresso no dominio realizado"

# ============================================================
# Configurar SSSD (se metodo for sssd ou both)
# ============================================================
if [ "$JOIN_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "sssd" ]; then
    echo ">>> Configurando SSSD..."
    OFFLINE_CACHE=""
    if [ "$OFFLINE_AUTH_ENABLED" = "true" ]; then
        DAYS="${OFFLINE_AUTH_DAYS:-3}"
        OFFLINE_CACHE="cache_credentials = true
    krb5_store_password_if_offline = true
    offline_credentials_expiration = ${DAYS}"
    fi

    cat > /etc/sssd/sssd.conf <<EOF
[sssd]
services = nss, pam, sudo
config_file_version = 2
domains = ${DOMINIO}

[domain/${DOMINIO}]
    id_provider = ad
    ad_domain = ${DOMINIO}
    ad_server = ${DC_IP}
    ad_hostname = $(hostname).${DOMINIO}
    ldap_id_mapping = true
    enumerate = false
    use_fully_qualified_names = false
    fallback_homedir = /home/%d/%u
    default_shell = /bin/bash
    ${OFFLINE_CACHE}
    dyndns_update = false
    sudo_provider = ad
    ldap_sudo_search_base = OU=sudoers,${OU_PADRAO}
EOF

    chmod 600 /etc/sssd/sssd.conf
    echo ">>> SSSD configurado"
fi

# ============================================================
# Configurar NSS (suporta SSSD e Winbind)
# ============================================================
echo ">>> Configurando NSS..."
if [ "$JOIN_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "winbind" ]; then
    cat > /etc/nsswitch.conf <<EOF
passwd:     files systemd winbind
shadow:     files winbind
group:      files systemd winbind
gshadow:    files

hosts:      files dns

services:   files
netgroup:   files
sudoers:    files

automount:  files
EOF
else
    cat > /etc/nsswitch.conf <<EOF
passwd:     files systemd sss
shadow:     files sss
group:      files systemd sss
gshadow:    files

hosts:      files dns

services:   files sss
netgroup:   files sss
sudoers:    files sss

automount:  files sss
EOF
fi

echo ">>> NSS configurado"

# ============================================================
# Configurar PAM (mkhomedir)
# ============================================================
echo ">>> Configurando PAM e mkhomedir..."
pam-auth-update --enable mkhomedir --force 2>/dev/null || true

# Garantir criacao automatica do home
if [ -f /etc/pam.d/common-session ]; then
    grep -q "pam_mkhomedir" /etc/pam.d/common-session || \
        echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" >> /etc/pam.d/common-session
fi

# Configurar Winbind no PAM se necessario
if [ "$JOIN_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "winbind" ]; then
    pam-auth-update --enable winbind 2>/dev/null || true
fi

echo ">>> PAM configurado"

# ============================================================
# Configurar sudo para grupos do dominio
# ============================================================
echo ">>> Configurando sudo..."
SUDO_FILE="/etc/sudoers.d/seederlinux-domain"
cat > "$SUDO_FILE" <<EOF
# SeederLinux - Acesso sudo para grupos do dominio
%${GRUPO_ADMIN_AD}    ALL=(ALL:ALL) ALL
%${GRUPO_ADMIN_LINUX}  ALL=(ALL:ALL) ALL
EOF

if [ -n "$GRUPO_DASTI" ] && [ "$GRUPO_DASTI" != "" ]; then
    echo "%${GRUPO_DASTI}    ALL=(ALL:ALL) ALL" >> "$SUDO_FILE"
fi

chmod 440 "$SUDO_FILE"
visudo -cf "$SUDO_FILE" || {
    echo ">>> ERRO: sintaxe do sudoers invalida"
    read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
    if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
        echo ">>> Instalacao abortada pelo usuario."
        exit 1
    fi
    echo ">>> Continuando apesar do erro..."
}

echo ">>> Sudo configurado"

# ============================================================
# Reiniciar servicos
# ============================================================
echo ">>> Reiniciando servicos..."
systemctl restart samba 2>/dev/null || true

if [ "$JOIN_METHOD" = "sssd" ] || [ "$AUTH_METHOD" = "sssd" ]; then
    systemctl restart sssd 2>/dev/null || true
    systemctl enable sssd 2>/dev/null || true
fi

if [ "$JOIN_METHOD" = "winbind" ] || [ "$AUTH_METHOD" = "winbind" ]; then
    systemctl restart winbind 2>/dev/null || true
    systemctl enable winbind 2>/dev/null || true
fi

echo ">>> [04] Ingresso no AD concluido!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    4,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Configuracao de Navegador (ordem 5) - core_browser.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracao de Navegador',
    'core_browser.sh',
    'Configura Firefox ESR e Chrome (homepage, proxy, bookmarks) via politicas corporativas.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_browser.sh
# SeederLinux Lite - Politicas Firefox/Chrome
# ============================================================================
# Configura politicas corporativas para Firefox ESR, Google Chrome e Chromium
# via arquivos de policies (JSON) no sistema.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "06 - Configurar politicas de navegadores"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
HOMEPAGE="{{HOMEPAGE}}"
PROXY_MODE="{{PROXY_MODE}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
PAC_URL="{{PAC_URL}}"
NO_PROXY="{{NO_PROXY}}"
DOMINIO="{{DOMINIO}}"
OM_ACRONYM="{{OM_ACRONYM}}"
CERTIFICATE_BUNDLE="{{CERTIFICATE_BUNDLE}}"

echo ">>> Homepage: $HOMEPAGE"
echo ">>> Modo de proxy: $PROXY_MODE"

# ============================================================
# Firefox ESR - Politicas (policies.json)
# ============================================================
echo ">>> Configurando politicas do Firefox ESR..."
mkdir -p /usr/lib/firefox-esr/distribution

cat > /usr/lib/firefox-esr/distribution/policies.json <<EOF
{
    "policies": {
        "DisableTelemetry": true,
        "DisableFirefoxStudies": true,
        "DisablePocket": true,
        "DisableDeveloperTools": false,
        "BlockAboutConfig": false,
        "Homepage": {
            "URL": "${HOMEPAGE}",
            "Locked": true,
            "StartPage": "homepage"
        },
        "HomepageURL": "${HOMEPAGE}",
        "SearchBar": "unified",
        "SearchEngines": {
            "Add": [
                {
                    "Name": "${OM_ACRONYM}",
                    "URL": "${HOMEPAGE}",
                    "Method": "GET"
                }
            ]
        },
        "Proxy": {
            "Mode": "system",
            "Locked": true
        },
        "Certificates": {
            "ImportEnterpriseRoots": true
        },
        "ExtensionSettings": {
            "*": {
                "installation_mode": "allowed"
            }
        },
        "DisableSetDesktopBackground": false,
        "DontCheckDefaultBrowser": true,
        "PrimaryPassword": false,
        "OfferToSaveLogins": false,
        "PasswordManagerEnabled": false,
        "SanitizeOnShutdown": {
            "Cache": true,
            "Cookies": false,
            "Downloads": false,
            "FormData": true,
            "History": false,
            "Sessions": false,
            "SiteSettings": false,
            "OfflineApps": false
        }
    }
}
EOF

echo ">>> Politicas do Firefox configuradas"

# ============================================================
# Firefox ESR - autoconfig (para proxy PAC)
# ============================================================
if [ "$PROXY_MODE" = "PAC" ]; then
    echo ">>> Configurando PAC no Firefox..."
    mkdir -p /usr/lib/firefox-esr/defaults/pref
    cat > /usr/lib/firefox-esr/defaults/pref/autoconfig.js <<EOF
pref("general.config.filename", "seederlinux.cfg");
pref("general.config.obscure_value", 0);
EOF

    cat > /usr/lib/firefox-esr/seederlinux.cfg <<EOF
lockPref("network.proxy.type", 2);
lockPref("network.proxy.autoconfig_url", "${PAC_URL}");
lockPref("network.proxy.no_proxies_on", "${NO_PROXY}");
EOF
    echo ">>> PAC configurado no Firefox"
elif [ "$PROXY_MODE" = "MANUAL" ]; then
    echo ">>> Configurando proxy manual no Firefox..."
    mkdir -p /usr/lib/firefox-esr/defaults/pref
    cat > /usr/lib/firefox-esr/defaults/pref/autoconfig.js <<EOF
pref("general.config.filename", "seederlinux.cfg");
pref("general.config.obscure_value", 0);
EOF

    cat > /usr/lib/firefox-esr/seederlinux.cfg <<EOF
lockPref("network.proxy.type", 1);
lockPref("network.proxy.http", "${PROXY_HTTP}");
lockPref("network.proxy.http_port", ${PROXY_PORTA});
lockPref("network.proxy.https", "${PROXY_HTTP}");
lockPref("network.proxy.https_port", ${PROXY_PORTA});
lockPref("network.proxy.no_proxies_on", "${NO_PROXY}");
EOF
    echo ">>> Proxy manual configurado no Firefox"
fi

# ============================================================
# Google Chrome - Politicas
# ============================================================
echo ">>> Configurando politicas do Google Chrome..."
mkdir -p /etc/opt/chrome/policies/managed
mkdir -p /etc/opt/chrome/policies/recommended

# Proxy config para Chrome
case "$PROXY_MODE" in
    NONE)
        CHROME_PROXY_MODE="direct"
        ;;
    MANUAL)
        CHROME_PROXY_MODE="fixed_servers"
        CHROME_PROXY_SERVERS="http=${PROXY_HTTP}:${PROXY_PORTA};https=${PROXY_HTTP}:${PROXY_PORTA}"
        ;;
    PAC)
        CHROME_PROXY_MODE="pac_script"
        CHROME_PROXY_PAC_URL="$PAC_URL"
        ;;
    *)
        CHROME_PROXY_MODE="system"
        ;;
esac

# Construir JSON de proxy
PROXY_JSON=""
if [ "$CHROME_PROXY_MODE" = "fixed_servers" ]; then
    PROXY_JSON=", \"ProxyMode\": \"${CHROME_PROXY_MODE}\", \"ProxyServer\": \"${CHROME_PROXY_SERVERS}\""
elif [ "$CHROME_PROXY_MODE" = "pac_script" ]; then
    PROXY_JSON=", \"ProxyMode\": \"${CHROME_PROXY_MODE}\", \"ProxyPacUrl\": \"${CHROME_PROXY_PAC_URL}\""
else
    PROXY_JSON=", \"ProxyMode\": \"${CHROME_PROXY_MODE}\""
fi

cat > /etc/opt/chrome/policies/managed/seederlinux.json <<EOF
{
    "HomepageLocation": "${HOMEPAGE}",
    "HomepageIsNewTabPage": false,
    "RestoreOnStartup": 1,
    "RestoreOnStartupURLs": ["${HOMEPAGE}"],
    "BrowserSignin": 0,
    "SyncDisabled": true,
    "BlockThirdPartyCookies": true,
    "BackgroundModeEnabled": false,
    "TelemetryReportingEnabled": false,
    "UrlKeyboardsEnabled": false${PROXY_JSON},
    "DefaultCookiesSetting": 1,
    "AutoSelectCertificateForUrls": ["{\"pattern\":\"https://*\",\"filter\":{}}"],
    "ChromeCertProtectorEnabled": false
}
EOF

echo ">>> Politicas do Chrome configuradas"

# ============================================================
# Chromium - Politicas (mesmas do Chrome)
# ============================================================
echo ">>> Configurando politicas do Chromium..."
mkdir -p /etc/chromium/policies/managed
mkdir -p /etc/chromium/policies/recommended

cp /etc/opt/chrome/policies/managed/seederlinux.json \
   /etc/chromium/policies/managed/seederlinux.json 2>/dev/null || true

echo ">>> Politicas do Chromium configuradas"

echo ">>> [06] Politicas de navegadores configuradas!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    5,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Agente de Inventario OCS (ordem 6) - core_inventory.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Agente de Inventario OCS',
    'core_inventory.sh',
    'Configura OCS Inventory Agent (sem apt-get; pacote instalado em core_packages.sh).',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_inventory.sh
# SeederLinux Lite - OCS Inventory Agent (configuracao apenas)
# ============================================================================
# Configura o agente do OCS Inventory para coleta de inventario
# automatica da estacao. A instalacao de pacotes e feita no core_packages.sh.
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "06 - Configurar OCS Inventory Agent"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
INVENTORY_ENABLED="{{INVENTORY_ENABLED}}"
OCS_SERVER="{{OCS_SERVER}}"
OCS_TAG="{{OCS_TAG}}"
GLPI_SERVER="{{GLPI_SERVER}}"

echo ">>> Inventario habilitado: $INVENTORY_ENABLED"

# ============================================================
# Verificar se o inventario esta habilitado
# ============================================================
if [ "$INVENTORY_ENABLED" != "true" ]; then
    echo ">>> Inventario desativado. Pulando configuracao."
    echo ">>> [06] OCS Inventory desativado."
    echo "============================================================"
    exit 0
fi

if [ -z "$OCS_SERVER" ] || [ "$OCS_SERVER" = "" ]; then
    echo ">>> AVISO: OCS_SERVER nao definido. Pulando configuracao."
    echo ">>> [06] OCS Inventory nao configurado (servidor ausente)."
    echo "============================================================"
    exit 0
fi

echo ">>> Servidor OCS: $OCS_SERVER"
echo ">>> Tag OCS: $OCS_TAG"

# ============================================================
# Verificar se o pacote foi instalado (no core_packages.sh)
# ============================================================
if ! command -v ocsinventory-agent &>/dev/null; then
    echo ">>> AVISO: ocsinventory-agent nao instalado. Pulando configuracao."
    echo ">>> [06] OCS Inventory nao configurado (pacote ausente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Configurar agente OCS
# ============================================================
echo ">>> Configurando agente OCS..."
mkdir -p /etc/ocsinventory-agent

cat > /etc/ocsinventory-agent/ocsinventory-agent.cfg <<EOF
# Configuracao do OCS Inventory Agent - SeederLinux
server = ${OCS_SERVER}
tag = ${OCS_TAG}
basepath = /var/lib/ocsinventory-agent
debug = 0
local = no
nosoftware = 0
verbose = 0
EOF

# Arquivo de configuracao para o modulo Perl
OCS_URL="http://${OCS_SERVER}/ocsinventory"
cat > /etc/ocsinventory-agent/modules.conf 2>/dev/null <<EOF
# Modulos do OCS Inventory Agent
OCS_MODE = HTTP
OCS_SERVER = ${OCS_SERVER}
OCS_TAG = ${OCS_TAG}
EOF

# Configurar cron para execucao periodica
echo ">>> Configurando cron do OCS..."
cat > /etc/cron.d/ocsinventory-agent <<EOF
# OCS Inventory Agent - SeederLinux
# Executa a cada 4 horas
0 */4 * * * root /usr/bin/ocsinventory-agent --server=${OCS_SERVER} --tag="${OCS_TAG}" --lazy 2>/dev/null
EOF
chmod 644 /etc/cron.d/ocsinventory-agent

# ============================================================
# Configurar GLPI (se disponivel)
# ============================================================
if [ -n "$GLPI_SERVER" ] && [ "$GLPI_SERVER" != "" ]; then
    echo ">>> Configurando integracao GLPI..."
    mkdir -p /etc/glpi-agent

    cat > /etc/glpi-agent/agent.cfg <<EOF
# Configuracao do GLPI Agent - SeederLinux
server = ${GLPI_SERVER}
tag = ${OCS_TAG}
EOF
fi

# ============================================================
# Execucao inicial do inventario
# ============================================================
echo ">>> Executando coleta inicial de inventario..."
ocsinventory-agent --server="$OCS_SERVER" --tag="$OCS_TAG" --lazy 2>/dev/null || {
    echo ">>> AVISO: Falha na coleta inicial. Sera refeito via cron."
}

echo ">>> [06] OCS Inventory configurado!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    6,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Configuracao de Impressoras (ordem 7) - core_printers.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracao de Impressoras',
    'core_printers.sh',
    'Configura CUPS e impressoras via servidor remoto.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_printers.sh
# SeederLinux Lite - CUPS e impressoras (configuracao apenas)
# ============================================================================
# Configura o CUPS e instala as impressoras compartilhadas via servidor
# de impressao. A instalacao de pacotes e feita no core_packages.sh.
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "07 - Configurar CUPS e impressoras"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
PRINT_SERVER="{{PRINT_SERVER}}"
DEFAULT_PRINTER="{{DEFAULT_PRINTER}}"
PRINTERS="{{PRINTERS}}"
DOMINIO="{{DOMINIO}}"

echo ">>> Servidor de impressao: $PRINT_SERVER"
echo ">>> Impressora padrao: $DEFAULT_PRINTER"

# ============================================================
# Verificar se ha servidor de impressao
# ============================================================
if [ -z "$PRINT_SERVER" ] || [ "$PRINT_SERVER" = "" ]; then
    echo ">>> AVISO: PRINT_SERVER nao definido. Pulando configuracao."
    echo ">>> [07] Impressoras nao configuradas (servidor ausente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Verificar se o CUPS foi instalado (no core_packages.sh)
# ============================================================
if ! command -v cupsctl &>/dev/null; then
    echo ">>> AVISO: CUPS nao instalado. Pulando configuracao."
    echo ">>> [07] Impressoras nao configuradas (CUPS ausente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Configurar CUPS
# ============================================================
echo ">>> Configurando CUPS..."

# Habilitar e iniciar CUPS
systemctl enable cups
systemctl start cups

# Permitir administracao remota e compartilhamento
cupsctl --remote-admin --remote-any --share-printers 2>/dev/null || true

# Configurar cupsd.conf
cat > /etc/cups/cupsd.conf <<EOF
# Configuracao CUPS - SeederLinux
Browsing On
BrowseLocalProtocols dnssd
DefaultAuthType Basic
WebInterface Yes

Listen localhost:631
Listen /run/cups/cups.sock

<Location />
    Order allow,deny
    Allow all
</Location>

<Location /admin>
    Order allow,deny
    Allow all
</Location>

<Location /admin/conf>
    AuthType Default
    Require user @SYSTEM
    Order allow,deny
    Allow all
</Location>
EOF

systemctl restart cups

# ============================================================
# Configurar impressoras via servidor CUPS remoto
# ============================================================
echo ">>> Configurando impressoras via servidor remoto..."

# Criar arquivo de configuracao client.conf do CUPS
cat > /etc/cups/client.conf <<EOF
# Cliente CUPS - SeederLinux
ServerName ${PRINT_SERVER}
EOF

# ============================================================
# Instalar cada impressora listada
# ============================================================
if [ -n "$PRINTERS" ] && [ "$PRINTERS" != "" ]; then
    echo ">>> Instalando impressoras listadas..."
    for PRINTER in $PRINTERS; do
        echo ">>> Configurando impressora: $PRINTER"
        # Adicionar impressora via lpadmin (IPP via servidor)
        lpadmin -p "$PRINTER" -E -v "ipp://${PRINT_SERVER}/printers/${PRINTER}" \
            -m everywhere 2>/dev/null || {
            echo ">>> AVISO: Falha ao adicionar impressora $PRINTER"
        }
    done
else
    echo ">>> Nenhuma impressora listada. Usando descoberta automatica."
    # Descoberta automatica via servidor remoto
    lpinfo -h "$PRINT_SERVER" -v 2>/dev/null | grep ipp | while read -r line; do
        PRINTER_URI=$(echo "$line" | awk '{print $2}')
        PRINTER_NAME=$(basename "$PRINTER_URI")
        echo ">>> Impressora encontrada: $PRINTER_NAME"
        lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m everywhere 2>/dev/null || true
    done
fi

# ============================================================
# Definir impressora padrao
# ============================================================
if [ -n "$DEFAULT_PRINTER" ] && [ "$DEFAULT_PRINTER" != "" ]; then
    echo ">>> Definindo impressora padrao: $DEFAULT_PRINTER"
    lpadmin -d "$DEFAULT_PRINTER" 2>/dev/null || {
        echo ">>> AVISO: Falha ao definir impressora padrao"
    }
fi

# ============================================================
# Reiniciar CUPS para aplicar
# ============================================================
systemctl restart cups

echo ">>> [07] CUPS e impressoras configurados!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    7,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Configuracao VNC (ordem 8) - core_vnc.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracao VNC',
    'core_vnc.sh',
    'Configura x11vnc para acesso remoto assistido.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_vnc.sh
# SeederLinux Lite - x11vnc (configuracao apenas)
# ============================================================================
# Configura o x11vnc para suporte remoto, incluindo servico systemd e
# senha de acesso. A instalacao de pacotes e feita no core_packages.sh.
#
# SEGURANCA: A senha VNC e gravada em /etc/seederlinux/secrets.env
# (perm 600) e usada diretamente com x11vnc -storepasswd.
#
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "08 - Configurar x11vnc"
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
    echo ">>> [08] x11vnc desativado."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Verificar se o x11vnc foi instalado (no core_packages.sh)
# ============================================================
if ! command -v x11vnc &>/dev/null; then
    echo ">>> AVISO: x11vnc nao instalado. Pulando configuracao."
    echo ">>> [08] x11vnc nao configurado (pacote ausente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Detectar Display Manager se nao definido
# ============================================================
if [ -z "$DISPLAY_MANAGER" ] || [ "$DISPLAY_MANAGER" = "" ]; then
    if systemctl is-active --quiet lightdm 2>/dev/null; then DISPLAY_MANAGER="lightdm"
    elif systemctl is-active --quiet gdm3 2>/dev/null; then DISPLAY_MANAGER="gdm3"
    elif systemctl is-active --quiet sddm 2>/dev/null; then DISPLAY_MANAGER="sddm"
    else DISPLAY_MANAGER="lightdm"
    fi
    echo ">>> Display Manager detectado: $DISPLAY_MANAGER"
fi

# ============================================================
# Configurar senha do VNC (SEM expor em texto plano)
# ============================================================
echo ">>> Configurando senha do VNC..."
mkdir -p /etc/x11vnc
mkdir -p /etc/seederlinux

SECRETS_FILE="/etc/seederlinux/secrets.env"

if [ -n "$VNC_PASSWORD" ] && [ "$VNC_PASSWORD" != "" ]; then
    x11vnc -storepasswd "$VNC_PASSWORD" /etc/x11vnc/vncpasswd
    chmod 600 /etc/x11vnc/vncpasswd
    echo ">>> Senha VNC configurada (fornecida pela OM)"
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
unset VNC_PASSWORD
unset RANDOM_PASS

# ============================================================
# Criar servico systemd para x11vnc
# ============================================================
echo ">>> Criando servico systemd x11vnc..."

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

echo ">>> [08] x11vnc configurado!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    8,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Configuracao de Conky (ordem 9) - core_conky.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracao de Conky',
    'core_conky.sh',
    'Configura o Conky (monitor de sistema no desktop) com perfil dinamico via JSON.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_conky.sh
# SeederLinux Lite - Conky (configuracao apenas)
# ============================================================================
# Configura o Conky para exibicao de informacoes do sistema no desktop,
# com perfil personalizavel. A instalacao de pacotes e feita no core_packages.sh.
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "09 - Configurar Conky"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
CONKY_PROFILE="{{CONKY_PROFILE}}"
CONKY_CONFIG='{{CONKY_CONFIG}}'
DESKTOP_ENV="{{DESKTOP_ENV}}"
OM_ACRONYM="{{OM_ACRONYM}}"
OM_NAME="{{OM_NAME}}"

echo ">>> Perfil Conky: $CONKY_PROFILE"
echo ">>> Ambiente: $DESKTOP_ENV"

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

# ============================================================
# Verificar se o Conky foi instalado (no core_packages.sh)
# ============================================================
if ! command -v conky &>/dev/null; then
    echo ">>> AVISO: Conky nao instalado. Pulando configuracao."
    echo ">>> [09] Conky nao configurado (pacote ausente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Parse do CONKY_CONFIG (JSON) com fallbacks
# ============================================================
parse_json() {
    local key="$1"
    local default="$2"
    local val
    val=$(echo "$CONKY_CONFIG" | jq -r "if has(\"${key}\") then .${key} else \"__UNSET__\" end" 2>/dev/null)
    if [ -z "$val" ] || [ "$val" = "null" ] || [ "$val" = "__UNSET__" ]; then
        echo "$default"
    else
        echo "$val"
    fi
}

CFG_POSITION=$(parse_json position "top_right")
CFG_TRANSPARENT=$(parse_json transparent "true")
CFG_COLOR_TEXT=$(parse_json color_text "#FFFFFF")
CFG_COLOR_BG=$(parse_json color_bg "#000000")
CFG_FONT_SIZE=$(parse_json font_size "10")
CFG_GAP_X=$(parse_json gap_x "10")
CFG_GAP_Y=$(parse_json gap_y "40")
CFG_UPDATE_INTERVAL=$(parse_json update_interval "1.0")
CFG_SHOW_CPU=$(parse_json show_cpu "true")
CFG_SHOW_RAM=$(parse_json show_ram "true")
CFG_SHOW_DISK=$(parse_json show_disk "true")
CFG_DISK_PARTITION=$(parse_json disk_partition "/")
CFG_SHOW_NETWORK=$(parse_json show_network "true")
CFG_NETWORK_IFACE=$(parse_json network_interface "eth0")
CFG_SHOW_TOP=$(parse_json show_top_processes "true")
CFG_SHOW_DATETIME=$(parse_json show_datetime "true")
CFG_SHOW_HOSTNAME=$(parse_json show_hostname "true")
CFG_HOSTNAME_FONT_SIZE=$(parse_json font_size_hostname "14")

COLOR_TEXT_LUA="${CFG_COLOR_TEXT#\#}"
COLOR_BG_LUA="${CFG_COLOR_BG#\#}"

if [ "$CFG_TRANSPARENT" = "true" ]; then
    OWN_TRANSPARENT="true"
    OWN_ARGB_VALUE="0"
else
    OWN_TRANSPARENT="false"
    OWN_ARGB_VALUE="200"
fi

# ============================================================
# Criar diretorio de configuracao global
# ============================================================
mkdir -p /etc/seederlinux/conky

# ============================================================
# Gerar configuracao do Conky (usando CONKY_CONFIG JSON)
# ============================================================
echo ">>> Gerando configuracao do Conky (CONKY_CONFIG=${CONKY_CONFIG:-vazio})..."

if [ "$CFG_SHOW_HOSTNAME" = "true" ]; then
    CONKY_TEXT="\${font DejaVu Sans Mono:size=${CFG_HOSTNAME_FONT_SIZE}}\${color ${COLOR_TEXT_LUA}}Host: \${nodename}
\${font DejaVu Sans Mono:size=${CFG_FONT_SIZE}}
\${color ${COLOR_TEXT_LUA}}${OM_ACRONYM} - ${OM_NAME}
\${color ${COLOR_TEXT_LUA}}\${hr}"
else
    CONKY_TEXT="\${color ${COLOR_TEXT_LUA}}${OM_ACRONYM} - ${OM_NAME}
\${color ${COLOR_TEXT_LUA}}\${hr}"
fi

CONKY_TEXT="${CONKY_TEXT}
\${color ${COLOR_TEXT_LUA}}Uptime: \${color grey}\${uptime}
\${color ${COLOR_TEXT_LUA}}\${hr}"

if [ "$CFG_SHOW_CPU" = "true" ]; then
    CONKY_TEXT="${CONKY_TEXT}
\${color ${COLOR_TEXT_LUA}}CPU:  \${color grey}\${cpu}% \${cpubar 4}"
fi
if [ "$CFG_SHOW_RAM" = "true" ]; then
    CONKY_TEXT="${CONKY_TEXT}
\${color ${COLOR_TEXT_LUA}}RAM:  \${color grey}\${mem}/\${memmax} \${membar 4}
\${color ${COLOR_TEXT_LUA}}SWAP: \${color grey}\${swap}/\${swapmax} \${swapbar 4}"
fi
if [ "$CFG_SHOW_DISK" = "true" ]; then
    CONKY_TEXT="${CONKY_TEXT}
\${color ${COLOR_TEXT_LUA}}Disco (${CFG_DISK_PARTITION}): \${color grey}\${fs_used ${CFG_DISK_PARTITION}}/\${fs_size ${CFG_DISK_PARTITION}} \${fs_bar 6 ${CFG_DISK_PARTITION}}"
fi
if [ "$CFG_SHOW_NETWORK" = "true" ]; then
    CONKY_TEXT="${CONKY_TEXT}
\${color ${COLOR_TEXT_LUA}}Rede (${CFG_NETWORK_IFACE}):
\${color ${COLOR_TEXT_LUA}}IP:   \${color grey}\${addr ${CFG_NETWORK_IFACE}}
\${color ${COLOR_TEXT_LUA}}Down: \${color grey}\${downspeed ${CFG_NETWORK_IFACE}}
\${color ${COLOR_TEXT_LUA}}Up:   \${color grey}\${upspeed ${CFG_NETWORK_IFACE}}"
fi
if [ "$CFG_SHOW_TOP" = "true" ]; then
    CONKY_TEXT="${CONKY_TEXT}
\${color ${COLOR_TEXT_LUA}}\${hr}
\${color ${COLOR_TEXT_LUA}}Top CPU:
\${color grey}\${top name 1} \${top cpu 1}%
\${color grey}\${top name 2} \${top cpu 2}%
\${color grey}\${top name 3} \${top cpu 3}%"
fi
if [ "$CFG_SHOW_DATETIME" = "true" ]; then
    CONKY_TEXT="${CONKY_TEXT}
\${color ${COLOR_TEXT_LUA}}\${hr}
\${color ${COLOR_TEXT_LUA}}\${time %A, %d/%m/%Y %H:%M:%S}"
fi

cat > /etc/seederlinux/conky/conky.conf <<EOF
-- Configuracao Conky - SeederLinux (gerada dinamicamente)
-- Perfil: ${CONKY_PROFILE:-default}

conky.config = {
    alignment = '${CFG_POSITION}',
    background = false,
    border_width = 1,
    cpu_avg_samples = 2,
    default_color = '${COLOR_TEXT_LUA}',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    font = 'DejaVu Sans Mono:size=${CFG_FONT_SIZE}',
    gap_x = ${CFG_GAP_X},
    gap_y = ${CFG_GAP_Y},
    minimum_width = 200,
    net_avg_samples = 2,
    no_buffers = true,
    own_window = true,
    own_window_class = 'Conky',
    own_window_type = 'desktop',
    own_window_argb_visual = true,
    own_window_argb_value = ${OWN_ARGB_VALUE},
    own_window_transparent = ${OWN_TRANSPARENT},
    own_window_colour = '${COLOR_BG_LUA}',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    update_interval = ${CFG_UPDATE_INTERVAL},
    use_xft = true,
}

conky.text = [[
${CONKY_TEXT}
]]
EOF

# ============================================================
# Criar script de inicializacao do Conky
# ============================================================
echo ">>> Criando script de inicializacao..."
cat > /usr/local/bin/seederlinux-conky <<'SCRIPT'
#!/bin/bash
CONKY_CONF="/etc/seederlinux/conky/conky.conf"
sleep 5
if [ -f "$CONKY_CONF" ]; then
    killall conky 2>/dev/null || true
    conky -c "$CONKY_CONF" &
else
    echo "Configuracao do Conky nao encontrada: $CONKY_CONF"
fi
SCRIPT

chmod +x /usr/local/bin/seederlinux-conky

# ============================================================
# Adicionar Conky ao autostart conforme o DE
# ============================================================
echo ">>> Configurando autostart do Conky para: $DESKTOP_ENV"

case "$DESKTOP_ENV" in
    cinnamon|mate|xfce|lxde|gnome)
        mkdir -p /etc/xdg/autostart
        cat > /etc/xdg/autostart/seederlinux-conky.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Conky (SeederLinux)
Exec=/usr/local/bin/seederlinux-conky
Terminal=false
X-GNOME-Autostart-enabled=true
NoDisplay=false
EOF
        ;;
    kde)
        mkdir -p /usr/share/autostart
        cat > /usr/share/autostart/seederlinux-conky.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Conky (SeederLinux)
Exec=/usr/local/bin/seederlinux-conky
Terminal=false
X-KDE-autostart-enabled=true
EOF
        ;;
esac

echo ">>> [09] Conky configurado!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    9,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Instalacao de Aplicacoes Extras (ordem 10) - core_apps.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Instalacao de Aplicacoes Extras',
    'core_apps.sh',
    'Instala aplicacoes extras (OnlyOffice, Chrome, etc).',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_apps.sh
# SeederLinux Lite - OnlyOffice, Chrome, Firefox ESR
# ============================================================================
# Instala aplicativos adicionais: OnlyOffice Desktop Editors, Google Chrome
# estavel e Firefox ESR.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "10 - Instalar aplicativos (Chrome, OnlyOffice via .deb/wget)"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
INSTALL_ONLYOFFICE="{{INSTALL_ONLYOFFICE}}"
INSTALL_CHROME="{{INSTALL_CHROME}}"
INSTALL_CHROMIUM="{{INSTALL_CHROMIUM}}"
BASE_URL="{{BASE_URL}}"
PROXY_MODE="{{PROXY_MODE}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"

echo ">>> Instalar OnlyOffice: $INSTALL_ONLYOFFICE"
echo ">>> Instalar Chrome: $INSTALL_CHROME"
echo ">>> Instalar Chromium: $INSTALL_CHROMIUM"

# ============================================================
# Verificar se pelo menos um toggle esta ativo
# ============================================================
if [ "$INSTALL_ONLYOFFICE" != "true" ] && [ "$INSTALL_CHROME" != "true" ] && [ "$INSTALL_CHROMIUM" != "true" ]; then
    echo ">>> Instalacao de apps desativada. Pulando."
    echo ">>> [10] Aplicativos nao instalados (desativado)."
    echo "============================================================"
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# Configurar proxy para downloads se necessario
if [ "$PROXY_MODE" = "MANUAL" ] && [ -n "$PROXY_HTTP" ] && [ "$PROXY_HTTP" != "" ]; then
    export http_proxy="http://${PROXY_HTTP}:${PROXY_PORTA}"
    export https_proxy="http://${PROXY_HTTP}:${PROXY_PORTA}"
fi

# ============================================================
# Google Chrome (instalado via .deb/wget, nao via apt-get)
# ============================================================
if [ "$INSTALL_CHROME" = "true" ]; then
    echo ">>> Instalando Google Chrome..."
    CHROME_DEB="/tmp/google-chrome-stable.deb"

    # Baixar Chrome
    if wget -q -O "$CHROME_DEB" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"; then
        apt-get install -y "$CHROME_DEB" || {
            echo ">>> AVISO: Falha ao instalar Google Chrome. Tentando dependencias..."
            apt-get install -y -f
            apt-get install -y "$CHROME_DEB" || {
                echo ">>> AVISO: Google Chrome nao instalado."
            }
        }
        rm -f "$CHROME_DEB"
    else
        echo ">>> AVISO: Nao foi possivel baixar Google Chrome."
        echo ">>> Verifique conectividade e configuracao de proxy."
    fi
else
    echo ">>> Google Chrome desativado (INSTALL_CHROME=false). Pulando."
fi

# ============================================================
# Chromium (via apt-get)
# ============================================================
if [ "$INSTALL_CHROMIUM" = "true" ]; then
    echo ">>> Instalando Chromium..."
    apt-get install -y chromium 2>/dev/null || apt-get install -y chromium-browser 2>/dev/null || {
        echo ">>> AVISO: Nao foi possivel instalar Chromium."
    }
else
    echo ">>> Chromium desativado (INSTALL_CHROMIUM=false). Pulando."
fi

# ============================================================
# OnlyOffice Desktop Editors
# ============================================================
if [ "$INSTALL_ONLYOFFICE" = "true" ]; then
    echo ">>> Instalando OnlyOffice Desktop Editors..."

# Metodo 1: Via repositorio APT oficial
ONLYOFFICE_KEY="/tmp/onlyoffice-key.asc"
ONLYOFFICE_REPO_LIST="/etc/apt/sources.list.d/onlyoffice.list"

# Baixar e adicionar chave GPG
if wget -q -O "$ONLYOFFICE_KEY" "https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE"; then
    gpg --dearmor < "$ONLYOFFICE_KEY" > /usr/share/keyrings/onlyoffice-keyring.gpg 2>/dev/null || \
        apt-key add "$ONLYOFFICE_KEY" 2>/dev/null || true

    cat > "$ONLYOFFICE_REPO_LIST" <<EOF
deb [signed-by=/usr/share/keyrings/onlyoffice-keyring.gpg] https://download.onlyoffice.com/repo/debian squeeze main
EOF

    apt-get update
    apt-get install -y onlyoffice-desktopeditors || {
        echo ">>> AVISO: Falha ao instalar OnlyOffice via repositorio."
        echo ">>> Tentando download direto..."

        # Metodo 2: Download direto do .deb
        ONLYOFFICE_DEB="/tmp/onlyoffice-desktopeditors.deb"
        if wget -q -O "$ONLYOFFICE_DEB" "https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb"; then
            apt-get install -y "$ONLYOFFICE_DEB" || {
                echo ">>> AVISO: Falha ao instalar OnlyOffice via .deb direto."
            }
            rm -f "$ONLYOFFICE_DEB"
        else
            echo ">>> AVISO: Nao foi possivel baixar OnlyOffice."
        fi
    }
    rm -f "$ONLYOFFICE_KEY"
else
    echo ">>> AVISO: Nao foi possivel obter chave do OnlyOffice."
    echo ">>> Tentando instalar via repositorio Debian..."

    apt-get install -y onlyoffice-desktopeditors 2>/dev/null || {
            echo ">>> AVISO: OnlyOffice nao disponivel. Instalacao ignorada."
        }
    fi
else
    echo ">>> OnlyOffice desativado (INSTALL_ONLYOFFICE=false). Pulando."
fi

# ============================================================
# Verificar instalacoes
# ============================================================
echo ">>> Verificando instalacoes..."
command -v firefox-esr &> /dev/null && echo ">>> Firefox ESR: OK" || echo ">>> Firefox ESR: NAO INSTALADO"
command -v google-chrome &> /dev/null && echo ">>> Google Chrome: OK" || echo ">>> Google Chrome: NAO INSTALADO"
command -v onlyoffice-desktopeditors &> /dev/null && echo ">>> OnlyOffice: OK" || echo ">>> OnlyOffice: NAO INSTALADO"

echo ">>> [10] Aplicativos instalados!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    10,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Suporte a Sistemas Legados (ordem 11) - core_legados.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Suporte a Sistemas Legados',
    'core_legados.sh',
    'Instala Java 8 e Firefox 52 ESR para compatibilidade com sistemas legados.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_legados.sh
# SeederLinux Lite - Java 8, Firefox 52.7 ESR (sistemas legados)
# ============================================================================
# Instala Java 8 (OpenJDK ou Oracle) e/ou Firefox 52.7 ESR para compatibilidade
# com sistemas legados (applets Java, sistemas antigos da intranet).
# Cada componente e controlado por seu proprio toggle:
#   INSTALL_JAVA8     - Instalar Java 8?
#   INSTALL_FIREFOX52 - Instalar Firefox 52.7 ESR?
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "11 - Configurar sistemas legados (Java 8, Firefox 52.7)"
echo "============================================================"

# ============================================================
# Variaveis
# ============================================================
INSTALL_JAVA8="{{INSTALL_JAVA8}}"
INSTALL_FIREFOX52="{{INSTALL_FIREFOX52}}"
BASE_URL="{{BASE_URL}}"
PROXY_MODE="{{PROXY_MODE}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
JAVA_EXCEPTIONS="{{JAVA_EXCEPTIONS}}"

echo ">>> Instalar Java 8: $INSTALL_JAVA8"
echo ">>> Instalar Firefox 52.7: $INSTALL_FIREFOX52"
echo ">>> Excecoes Java: ${JAVA_EXCEPTIONS:-nenhuma}"

# ============================================================
# Verificar se pelo menos um toggle esta ativo
# ============================================================
if [ "$INSTALL_JAVA8" != "true" ] && [ "$INSTALL_FIREFOX52" != "true" ]; then
    echo ">>> Sistemas legados desativados. Pulando."
    echo ">>> [11] Sistemas legados nao instalados (desativado)."
    echo "============================================================"
    exit 0
fi

export DEBIAN_FRONTEND=noninteractive

# Configurar proxy para downloads
if [ "$PROXY_MODE" = "MANUAL" ] && [ -n "$PROXY_HTTP" ] && [ "$PROXY_HTTP" != "" ]; then
    export http_proxy="http://${PROXY_HTTP}:${PROXY_PORTA}"
    export https_proxy="http://${PROXY_HTTP}:${PROXY_PORTA}"
fi

# ============================================================
# Java 8 (OpenJDK 8) - apenas se INSTALL_JAVA8=true
# ============================================================
if [ "$INSTALL_JAVA8" = "true" ]; then
    echo ">>> Instalando Java 8 (OpenJDK 8)..."

    # Verificar se ja esta instalado (foi instalado no core_packages.sh)
    if command -v java &>/dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -1)
        echo ">>> Java ja instalado: $JAVA_VERSION"
    else
        echo ">>> AVISO: Java 8 nao foi instalado no core_packages.sh."
        echo ">>> Tentando instalar via repositorio Adoptium/Temurin..."

        if wget -q -O /tmp/adoptium-key.asc "https://packages.adoptium.net/artifactory/api/gpg/key/public" 2>/dev/null; then
            gpg --dearmor < /tmp/adoptium-key.asc > /usr/share/keyrings/adoptium-keyring.gpg 2>/dev/null || true
            echo "deb [signed-by=/usr/share/keyrings/adoptium-keyring.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" \
                > /etc/apt/sources.list.d/adoptium.list
            apt-get update
            apt-get install -y temurin-8-jre || {
                echo ">>> AVISO: Falha ao instalar Java 8 via Adoptium."
            }
            rm -f /tmp/adoptium-key.asc
        else
            echo ">>> AVISO: Nao foi possivel obter chave do repositorio Java 8."
        fi
    fi

    # Configurar excecoes Java (deployment.properties) se fornecidas
    if [ -n "$JAVA_EXCEPTIONS" ] && [ "$JAVA_EXCEPTIONS" != "" ]; then
        echo ">>> Configurando excecoes Java..."
        DEPLOY_DIR="/usr/lib/jvm/.deployment"
        mkdir -p "$DEPLOY_DIR"
        DEPLOY_FILE="$DEPLOY_DIR/deployment.properties"
        echo "# Excecoes Java - SeederLinux" > "$DEPLOY_FILE"
        echo "deployment.security.level=MEDIUM" >> "$DEPLOY_FILE"
        # Processar cada URL (uma por linha ou separada por virgula)
        IFS=
else
    echo ">>> Java 8 desativado (INSTALL_JAVA8=false). Pulando."
fi

# ============================================================
# Firefox 52.7 ESR (para applets Java) - apenas se INSTALL_FIREFOX52=true
# ============================================================
if [ "$INSTALL_FIREFOX52" = "true" ]; then
    echo ">>> Instalando Firefox 52.7 ESR..."

    FF_LEGADO_DIR="/opt/firefox-legado"
    FF_LEGADO_TARBALL="/tmp/firefox-52.7-esr.tar.bz2"
    FF_LEGADO_URL="${BASE_URL}/downloads/firefox-52.7.3esr.tar.bz2"

    mkdir -p /opt

    # Tentar baixar do repositorio interno
    if wget -q -O "$FF_LEGADO_TARBALL" "$FF_LEGADO_URL" 2>/dev/null; then
        echo ">>> Firefox 52.7 baixado do repositorio interno"
        tar xjf "$FF_LEGADO_TARBALL" -C /opt/
        mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
        rm -f "$FF_LEGADO_TARBALL"
    else
        echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7 do repositorio interno."
        echo ">>> Tentando download da Mozilla..."

        FF_MOZILLA_URL="https://ftp.mozilla.org/pub/firefox/releases/52.7.3esr/linux-x86_64/en-US/firefox-52.7.3esr.tar.bz2"
        if wget -q -O "$FF_LEGADO_TARBALL" "$FF_MOZILLA_URL" 2>/dev/null; then
            tar xjf "$FF_LEGADO_TARBALL" -C /opt/
            mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
            rm -f "$FF_LEGADO_TARBALL"
        else
            echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7."
        fi
    fi

    # Criar link simbolico
    if [ -d "$FF_LEGADO_DIR" ]; then
        ln -sf "${FF_LEGADO_DIR}/firefox" /usr/local/bin/firefox-legado
        echo ">>> Firefox 52.7 ESR instalado em: $FF_LEGADO_DIR"

        # Criar entrada de desktop
        mkdir -p /usr/share/applications
        cat > /usr/share/applications/firefox-legado.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=Firefox 52.7 ESR (Legado)
Comment=Navegador Firefox 52.7 ESR para sistemas legados
Exec=${FF_LEGADO_DIR}/firefox
Icon=${FF_LEGADO_DIR}/browser/icons/mozicon128.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF
        echo ">>> Entrada de desktop criada"
    else
        echo ">>> AVISO: Firefox 52.7 ESR nao instalado."
    fi

    # Configurar plugin Java para Firefox legado
    echo ">>> Configurando plugin Java para Firefox legado..."
    if [ -d "$FF_LEGADO_DIR" ] && command -v java &> /dev/null; then
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
        PLUGIN_DIR="${FF_LEGADO_DIR}/browser/plugins"
        mkdir -p "$PLUGIN_DIR"

        # Localizar libnpjp2.so
        find "$JAVA_HOME" -name "libnpjp2.so" -exec ln -sf {} "$PLUGIN_DIR/libnpjp2.so" \; 2>/dev/null || {
            echo ">>> AVISO: Plugin Java (libnpjp2.so) nao encontrado."
        }
        echo ">>> Plugin Java configurado"
    fi
else
    echo ">>> Firefox 52.7 desativado (INSTALL_FIREFOX52=false). Pulando."
fi

echo ">>> [11] Sistemas legados configurados!"
echo "============================================================"
\n,' read -ra EXC_URLS <<< "$JAVA_EXCEPTIONS"
        IDX=0
        for EXC_URL in "${EXC_URLS[@]}"; do
            EXC_URL=$(echo "$EXC_URL" | xargs)
            if [ -n "$EXC_URL" ] && [ "$EXC_URL" != "" ]; then
                echo "deployment.security.sandbox.awtwarningwindow=false" >> "$DEPLOY_FILE"
                echo "# Excecao $IDX: $EXC_URL" >> "$DEPLOY_FILE"
                # Adicionar a lista de excecoes
                echo "javaws.allow.0=$EXC_URL" >> "$DEPLOY_FILE"
                IDX=$((IDX+1))
            fi
        done
        echo ">>> Excecoes Java configuradas ($IDX URLs)"
    fi

    # Verificar Java 8
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -1)
        echo ">>> Java instalado: $JAVA_VERSION"
    else
        echo ">>> AVISO: Java nao instalado."
    fi
else
    echo ">>> Java 8 desativado (INSTALL_JAVA8=false). Pulando."
fi

# ============================================================
# Firefox 52.7 ESR (para applets Java) - apenas se INSTALL_FIREFOX52=true
# ============================================================
if [ "$INSTALL_FIREFOX52" = "true" ]; then
    echo ">>> Instalando Firefox 52.7 ESR..."

    FF_LEGADO_DIR="/opt/firefox-legado"
    FF_LEGADO_TARBALL="/tmp/firefox-52.7-esr.tar.bz2"
    FF_LEGADO_URL="${BASE_URL}/downloads/firefox-52.7.3esr.tar.bz2"

    mkdir -p /opt

    # Tentar baixar do repositorio interno
    if wget -q -O "$FF_LEGADO_TARBALL" "$FF_LEGADO_URL" 2>/dev/null; then
        echo ">>> Firefox 52.7 baixado do repositorio interno"
        tar xjf "$FF_LEGADO_TARBALL" -C /opt/
        mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
        rm -f "$FF_LEGADO_TARBALL"
    else
        echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7 do repositorio interno."
        echo ">>> Tentando download da Mozilla..."

        FF_MOZILLA_URL="https://ftp.mozilla.org/pub/firefox/releases/52.7.3esr/linux-x86_64/en-US/firefox-52.7.3esr.tar.bz2"
        if wget -q -O "$FF_LEGADO_TARBALL" "$FF_MOZILLA_URL" 2>/dev/null; then
            tar xjf "$FF_LEGADO_TARBALL" -C /opt/
            mv /opt/firefox "$FF_LEGADO_DIR" 2>/dev/null || true
            rm -f "$FF_LEGADO_TARBALL"
        else
            echo ">>> AVISO: Nao foi possivel baixar Firefox 52.7."
        fi
    fi

    # Criar link simbolico
    if [ -d "$FF_LEGADO_DIR" ]; then
        ln -sf "${FF_LEGADO_DIR}/firefox" /usr/local/bin/firefox-legado
        echo ">>> Firefox 52.7 ESR instalado em: $FF_LEGADO_DIR"

        # Criar entrada de desktop
        mkdir -p /usr/share/applications
        cat > /usr/share/applications/firefox-legado.desktop <<EOF
[Desktop Entry]
Version=1.0
Name=Firefox 52.7 ESR (Legado)
Comment=Navegador Firefox 52.7 ESR para sistemas legados
Exec=${FF_LEGADO_DIR}/firefox
Icon=${FF_LEGADO_DIR}/browser/icons/mozicon128.png
Terminal=false
Type=Application
Categories=Network;WebBrowser;
EOF
        echo ">>> Entrada de desktop criada"
    else
        echo ">>> AVISO: Firefox 52.7 ESR nao instalado."
    fi

    # Configurar plugin Java para Firefox legado
    echo ">>> Configurando plugin Java para Firefox legado..."
    if [ -d "$FF_LEGADO_DIR" ] && command -v java &> /dev/null; then
        JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
        PLUGIN_DIR="${FF_LEGADO_DIR}/browser/plugins"
        mkdir -p "$PLUGIN_DIR"

        # Localizar libnpjp2.so
        find "$JAVA_HOME" -name "libnpjp2.so" -exec ln -sf {} "$PLUGIN_DIR/libnpjp2.so" \; 2>/dev/null || {
            echo ">>> AVISO: Plugin Java (libnpjp2.so) nao encontrado."
        }
        echo ">>> Plugin Java configurado"
    fi
else
    echo ">>> Firefox 52.7 desativado (INSTALL_FIREFOX52=false). Pulando."
fi

echo ">>> [11] Sistemas legados configurados!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    11,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Configuracoes Adicionais (ordem 12) - core_config.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracoes Adicionais',
    'core_config.sh',
    'Configuracoes diversas do sistema (sysctl, limits, etc).',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_config.sh
# SeederLinux Lite - Arquivo de Configuracao Persistente
# ============================================================================
# Cria /etc/seederlinux/config.env com todas as variaveis nao-sensiveis
# da OM. Este arquivo e lido pelos scripts permanentes (seederlinux-logon,
# seederlinux-logoff) apos reboot, quando as variaveis exportadas no bundle
# ja nao existem mais na memoria.
#
# Variaveis sensiveis (senha VNC, usuario admin do AD) NAO sao escritas
# neste arquivo. Elas sao gravadas em /etc/seederlinux/secrets.env (perm 600)
# apenas pelo core_vnc.sh e core_domain.sh respectivamente.
#
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "13.5 - Criar arquivo de configuracao persistente"
echo "============================================================"

# ============================================================
# Diretorio base
# ============================================================
mkdir -p /etc/seederlinux

CONFIG_FILE="/etc/seederlinux/config.env"

# ============================================================
# Escrever variaveis nao-sensiveis no config.env
# Variaveis sensiveis (VNC_PASSWORD, ADMIN_USERNAME) ficam em
# /etc/seederlinux/secrets.env, gravadas por seus respectivos scripts.
# ============================================================
cat > "$CONFIG_FILE" <<EOF
# SeederLinux Lite - Configuracao Persistente
# NAO EDITAR MANUALMENTE - gerado pelo core_config.sh
# Gerado em: $(date '+%Y-%m-%d %H:%M:%S')

# Dominio e Autenticacao
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
DC_IP="{{DC_IP}}"
DC_IP_LIST="{{DC_IP_LIST}}"
DC_SECUNDARIO_IP="{{DC_SECUNDARIO_IP}}"
DNS_PRIMARIO="{{DNS_PRIMARIO}}"
DNS_SECUNDARIO="{{DNS_SECUNDARIO}}"
DNS_INTERNET="{{DNS_INTERNET}}"
NTP_SERVER="{{NTP_SERVER}}"
OU_PADRAO="{{OU_PADRAO}}"
GRUPO_ADMIN="{{GRUPO_ADMIN}}"
GRUPO_ADMIN_AD="{{GRUPO_ADMIN_AD}}"
GRUPO_ADMIN_LINUX="{{GRUPO_ADMIN_LINUX}}"
GRUPO_DASTI="{{GRUPO_DASTI}}"
AUTH_METHOD="{{AUTH_METHOD}}"
OFFLINE_AUTH_ENABLED="{{OFFLINE_AUTH_ENABLED}}"
OFFLINE_AUTH_DAYS="{{OFFLINE_AUTH_DAYS}}"

# Rede e Proxy
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
PROXY_URL="{{PROXY_URL}}"
PROXY_MODE="{{PROXY_MODE}}"
PAC_URL="{{PAC_URL}}"
NO_PROXY="{{NO_PROXY}}"

# URLs e Servidores
BASE_URL="{{BASE_URL}}"
HOMEPAGE="{{HOMEPAGE}}"
OCS_SERVER="{{OCS_SERVER}}"
OCS_TAG="{{OCS_TAG}}"
GLPI_SERVER="{{GLPI_SERVER}}"
PRINT_SERVER="{{PRINT_SERVER}}"
SERVIDOR_ARQUIVOS="{{SERVIDOR_ARQUIVOS}}"

# Identidade Visual
OM_ACRONYM="{{OM_ACRONYM}}"
OM_NAME="{{OM_NAME}}"
DISPLAY_NAME="{{DISPLAY_NAME}}"
WALLPAPER_URL="{{WALLPAPER_URL}}"
WALLPAPER_LOGIN_URL="{{WALLPAPER_LOGIN_URL}}"
LOGO_URL="{{LOGO_URL}}"
GREETER_URL="{{GREETER_URL}}"
THEME="{{THEME}}"

# Ambiente Grafico
DESKTOP_ENV="{{DESKTOP_ENV}}"
DISPLAY_MANAGER="{{DISPLAY_MANAGER}}"

# Aplicacoes e Funcionalidades (toggles individuais)
INSTALL_ONLYOFFICE="{{INSTALL_ONLYOFFICE}}"
INSTALL_CHROME="{{INSTALL_CHROME}}"
INSTALL_CHROMIUM="{{INSTALL_CHROMIUM}}"
INSTALL_JAVA8="{{INSTALL_JAVA8}}"
INSTALL_FIREFOX52="{{INSTALL_FIREFOX52}}"
INSTALL_LEGADOS="{{INSTALL_LEGADOS}}"
VNC_ENABLED="{{VNC_ENABLED}}"
INVENTORY_ENABLED="{{INVENTORY_ENABLED}}"

# Repositorios
REPOSITORY_MODE="{{REPOSITORY_MODE}}"
REPOSITORY_URL="{{REPOSITORY_URL}}"
REPOSITORY_FALLBACK="{{REPOSITORY_FALLBACK}}"

# Compartilhamentos e Impressoras
COMPARTILHAMENTOS="{{COMPARTILHAMENTOS}}"
MOUNT_BASE="{{MOUNT_BASE}}"
DEFAULT_PRINTER="{{DEFAULT_PRINTER}}"
PRINTERS="{{PRINTERS}}"

# Acesso Remoto
REMOTE_METHOD="{{REMOTE_METHOD}}"
SSH_PORT="{{SSH_PORT}}"
SSH_GROUPS="{{SSH_GROUPS}}"

# Certificados
CERTIFICATE_BUNDLE="{{CERTIFICATE_BUNDLE}}"
CERTIFICATE_AUTO_INSTALL="{{CERTIFICATE_AUTO_INSTALL}}"

# Conky
CONKY_PROFILE="{{CONKY_PROFILE}}"
CONKY_CONFIG='{{CONKY_CONFIG}}'

# Servidor SeederLinux (para o agente Python)
SEEDER_SERVER="{{SEEDER_SERVER}}"
EOF

chmod 644 "$CONFIG_FILE"

echo ">>> Configuracao persistente gravada em $CONFIG_FILE"
echo ">>> [13.5] Arquivo de configuracao criado!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    12,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Identidade Visual (Branding) (ordem 13) - core_branding.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Identidade Visual (Branding)',
    'core_branding.sh',
    'Aplica wallpaper, logo, tema GTK e branding da OM.',
    $SeederScript$#!/bin/bash
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
$SeederScript$,
    TRUE,
    TRUE,
    13,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Script de Logon Persistente (ordem 14) - core_logon.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Script de Logon Persistente',
    'core_logon.sh',
    'Script executado a cada logon de usuario (multi-DE).',
    $SeederScript$#!/bin/bash
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
$SeederScript$,
    TRUE,
    TRUE,
    14,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Script de Logoff Persistente (ordem 15) - core_logoff.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Script de Logoff Persistente',
    'core_logoff.sh',
    'Script executado a cada logoff de usuario.',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_logoff.sh
# SeederLinux Lite - Logoff multi-DE
# ============================================================================
# Script executado no momento do logoff do usuario. Cria o script permanente
# /usr/local/bin/seederlinux-logoff que sera chamado pelo display manager
# (LightDM/GDM3/SDDM) a cada logoff, apos reboot.
#
# O script permanente detecta automaticamente o ambiente grafico, desmonta
# compartilhamentos CIFS, limpa cache e temporarios, e encerra processos.
# Le as variaveis de /etc/seederlinux/config.env (persistente).
#
# Os placeholders {{VARIAVEL}} sao substituidos automaticamente
# pelo sistema na geracao do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "15 - Logoff do usuario (multi-DE)"
echo "============================================================"

# ============================================================
# Variaveis (substituidas no bundle)
# ============================================================
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
SERVIDOR_ARQUIVOS="{{SERVIDOR_ARQUIVOS}}"
COMPARTILHAMENTOS="{{COMPARTILHAMENTOS}}"
MOUNT_BASE="{{MOUNT_BASE}}"
DESKTOP_ENV="{{DESKTOP_ENV}}"

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
# 1. Criar o script PERMANENTE em /usr/local/bin/seederlinux-logoff
# ============================================================
echo ">>> Criando script permanente: /usr/local/bin/seederlinux-logoff"

cat > /usr/local/bin/seederlinux-logoff <<'PERMSCRIPT'
#!/bin/bash
# seederlinux-logoff - Script permanente de logoff do SeederLinux (multi-DE)
# Executado pelo display manager (LightDM/GDM3/SDDM) a cada logoff.
# Le as variaveis de /etc/seederlinux/config.env (persistente).

CONFIG_FILE="/etc/seederlinux/config.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo ">>> [logoff] AVISO: $CONFIG_FILE nao encontrado. Logoff sem configuracao."
    exit 0
fi

USERNAME="${USER:-$(whoami)}"
USER_HOME="${HOME:-/home/$USERNAME}"
LOG_DIR="/var/log/logon-logoff"
LOG_FILE="$LOG_DIR/logoff_${USERNAME}.log"

mkdir -p "$LOG_DIR"

exec >> "$LOG_FILE" 2>&1
echo "=== Logoff: $(date) - Usuario: $USERNAME ==="

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

DESKTOP_ENV=$(detect_de)
echo ">>> [logoff] Ambiente: $DESKTOP_ENV"

# ============================================================
# Desmontar compartilhamentos CIFS do usuario
# ============================================================
if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    MOUNT_DIR="${MOUNT_BASE:-/mnt}"
    for SHARE in $COMPARTILHAMENTOS; do
        SHARE_MOUNT="${MOUNT_DIR}/${SHARE}"
        if mountpoint -q "$SHARE_MOUNT" 2>/dev/null; then
            umount "$SHARE_MOUNT" 2>/dev/null || {
                echo ">>> [logoff] AVISO: Falha ao desmontar ${SHARE_MOUNT}"
                umount -l "$SHARE_MOUNT" 2>/dev/null || true
            }
            echo ">>> [logoff] Compartilhamento desmontado: ${SHARE}"
        fi
    done
fi

# ============================================================
# Limpar cache de navegadores
# ============================================================
rm -rf "$USER_HOME/.cache/mozilla" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/google-chrome" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/chromium" 2>/dev/null || true

# ============================================================
# Esvaziar lixeira
# ============================================================
rm -rf "$USER_HOME/.local/share/Trash"/* 2>/dev/null || true

# ============================================================
# Remover temporarios do usuario
# ============================================================
find /tmp -user "$USERNAME" -type f -mmin +60 -delete 2>/dev/null || true
rm -rf "$USER_HOME/.cache/thumbnails" 2>/dev/null || true

# ============================================================
# Remover atalhos temporarios do desktop (compartilhamentos desmontados)
# ============================================================
if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    for SHARE in $COMPARTILHAMENTOS; do
        rm -f "$USER_HOME/Desktop/${SHARE}.desktop" 2>/dev/null || true
    done
fi

# ============================================================
# Matar processos do usuario (conky, x11vnc)
# ============================================================
killall -u "$USERNAME" conky 2>/dev/null || true
killall -u "$USERNAME" x11vnc 2>/dev/null || true

# ============================================================
# Rotacionar logs (manter 7 dias)
# ============================================================
find "$LOG_DIR" -name "logoff_*.log" -mtime +7 -delete 2>/dev/null || true
find "$LOG_DIR" -name "logon_*.log" -mtime +7 -delete 2>/dev/null || true

echo "=== Logoff concluido: $(date) ==="
exit 0
PERMSCRIPT

chmod 755 /usr/local/bin/seederlinux-logoff
echo ">>> Script permanente criado: /usr/local/bin/seederlinux-logoff"

# ============================================================
# 2. Executar logica de logoff AGORA (durante o bundle)
# ============================================================
echo ">>> Executando logica de logoff (bundle)..."

USERNAME="${USER:-$(whoami)}"
USER_HOME="${HOME:-/home/$USERNAME}"

echo ">>> [logoff] Usuario: $USERNAME"

if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    MOUNT_DIR="${MOUNT_BASE:-/mnt}"
    for SHARE in $COMPARTILHAMENTOS; do
        SHARE_MOUNT="${MOUNT_DIR}/${SHARE}"
        if mountpoint -q "$SHARE_MOUNT" 2>/dev/null; then
            umount "$SHARE_MOUNT" 2>/dev/null || {
                echo ">>> [logoff] AVISO: Falha ao desmontar ${SHARE_MOUNT}"
                umount -l "$SHARE_MOUNT" 2>/dev/null || true
            }
            echo ">>> [logoff] Compartilhamento desmontado: ${SHARE}"
        fi
    done
fi

rm -rf "$USER_HOME/.cache/mozilla" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/google-chrome" 2>/dev/null || true
rm -rf "$USER_HOME/.cache/chromium" 2>/dev/null || true
rm -rf "$USER_HOME/.local/share/Trash"/* 2>/dev/null || true
find /tmp -user "$USERNAME" -type f -mmin +60 -delete 2>/dev/null || true
rm -rf "$USER_HOME/.cache/thumbnails" 2>/dev/null || true

if [ -n "$COMPARTILHAMENTOS" ] && [ "$COMPARTILHAMENTOS" != "" ]; then
    for SHARE in $COMPARTILHAMENTOS; do
        rm -f "$USER_HOME/Desktop/${SHARE}.desktop" 2>/dev/null || true
    done
fi

killall -u "$USERNAME" conky 2>/dev/null || true
killall -u "$USERNAME" x11vnc 2>/dev/null || true

echo ">>> [15] Logoff concluido!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    15,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Sessao LightDM (ordem 16) - core_session_lightdm.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Sessao LightDM',
    'core_session_lightdm.sh',
    'Configura LightDM como display manager (autoselecao via DISPLAY_MANAGER=lightdm).',
    $SeederScript$#!/bin/bash
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
$SeederScript$,
    TRUE,
    TRUE,
    16,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Sessao GDM3 (ordem 16) - core_session_gdm3.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Sessao GDM3',
    'core_session_gdm3.sh',
    'Configura GDM3 como display manager (autoselecao via DISPLAY_MANAGER=gdm3).',
    $SeederScript$#!/bin/bash
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
$SeederScript$,
    TRUE,
    TRUE,
    16,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Sessao SDDM (ordem 16) - core_session_sddm.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Sessao SDDM',
    'core_session_sddm.sh',
    'Configura SDDM como display manager (autoselecao via DISPLAY_MANAGER=sddm).',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_session_sddm.sh
# SeederLinux Lite - SDDM: logon/logoff (KDE)
# ============================================================================
# Configura o SDDM como display manager e define os scripts de logon
# e logoff que serao executados nas transicoes de sessao.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "14c - Configurar SDDM (KDE)"
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
if [ "$DISPLAY_MANAGER" != "sddm" ]; then
    echo ">>> Display Manager nao e sddm. Pulando este script."
    echo ">>> [14c] SDDM nao configurado (DM diferente)."
    echo "============================================================"
    exit 0
fi

# ============================================================
# Instalar SDDM
# ============================================================
echo ">>> Instalando SDDM..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y sddm sddm-theme-breeze

# Garantir que o SDDM seja o DM padrao
echo "sddm shared/default-x-display-manager select sddm" | debconf-set-selections 2>/dev/null || true
echo "sddm sddm/daemon_name string sddm" | debconf-set-selections 2>/dev/null || true

# ============================================================
# Configurar SDDM
# ============================================================
echo ">>> Configurando SDDM..."
mkdir -p /etc/sddm.conf.d

cat > /etc/sddm.conf.d/seederlinux.conf <<EOF
# Configuracao SDDM - SeederLinux
[Theme]
Current=breeze
ThemeDir=/usr/share/sddm/themes

[Users]
MaximumUid=60000
MinimumUid=1000

[Autologin]
User=
Session=
EOF

echo ">>> SDDM configurado"

# ============================================================
# Configurar scripts de logon/logoff via Xsession
# ============================================================
echo ">>> Configurando scripts de logon/logoff no SDDM..."

# SDDM executa /etc/X11/Xsession que por sua vez pode chamar scripts.
# Para integrar logon/logoff, usamos o Xsetup e Xstop do SDDM.

# Xsetup - executado antes da sessao (logon)
XSETUP_FILE="/usr/share/sddm/scripts/Xsetup"
mkdir -p /usr/share/sddm/scripts

cat > "$XSETUP_FILE" <<'XSETUP'
#!/bin/bash
# Xsetup do SDDM - SeederLinux
# Executa o script de logon do SeederLinux
if [ -x /usr/local/bin/seederlinux-logon ]; then
    /usr/local/bin/seederlinux-logon "$@"
fi

exit 0
XSETUP
chmod +x "$XSETUP_FILE"

# Xstop - executado apos a sessao (logoff)
XSTOP_FILE="/usr/share/sddm/scripts/Xstop"

cat > "$XSTOP_FILE" <<'XSTOP'
#!/bin/bash
# Xstop do SDDM - SeederLinux
# Executa o script de logoff do SeederLinux
if [ -x /usr/local/bin/seederlinux-logoff ]; then
    /usr/local/bin/seederlinux-logoff "$@"
fi

exit 0
XSTOP
chmod +x "$XSTOP_FILE"

echo ">>> Scripts de logon/logoff configurados no SDDM"

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
systemctl disable gdm3 2>/dev/null || true
systemctl enable sddm

# ============================================================
# Reiniciar servico
# ============================================================
echo ">>> Reiniciando SDDM..."
systemctl restart sddm 2>/dev/null || {
    echo ">>> AVISO: SDDM sera iniciado no proximo boot."
}

echo ">>> [14c] SDDM configurado!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    16,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;


-- ============================================================================
-- Configuracao de Proxy (ordem 17) - core_proxy.sh
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, is_active, execution_order, version, organization_id)
VALUES (
    'Configuracao de Proxy',
    'core_proxy.sh',
    'Configura proxy corporativo no sistema (apt, curl, wget, env).',
    $SeederScript$#!/bin/bash
# ============================================================================
# Core Script: core_proxy.sh
# SeederLinux Lite - Proxy do sistema
# ============================================================================
# Configura o proxy HTTP/HTTPS no nivel do sistema (/etc/environment,
# /etc/apt/apt.conf.d) e em variaveis de ambiente globais.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "ATENCAO: Proxy sera configurado agora."
echo "Todos os pacotes ja foram instalados."
echo "A partir deste ponto, a internet pode exigir autenticacao."
echo "============================================================"
echo "17 - Configurar proxy do sistema"
echo "============================================================"

# ============================================================
# Variáveis
# ============================================================
PROXY_MODE="{{PROXY_MODE}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
PROXY_URL="{{PROXY_URL}}"
PAC_URL="{{PAC_URL}}"
NO_PROXY="{{NO_PROXY}}"

echo ">>> Modo de proxy: $PROXY_MODE"

# ============================================================
# Configurar conforme o modo
# ============================================================
case "$PROXY_MODE" in
    NONE)
        echo ">>> Proxy desativado (NONE)"
        # Remover configuracoes de proxy existentes
        rm -f /etc/apt/apt.conf.d/95seederlinux-proxy 2>/dev/null || true
        # Limpar /etc/environment de entradas de proxy
        if [ -f /etc/environment ]; then
            sed -i '/^http_proxy=/d; /^https_proxy=/d; /^ftp_proxy=/d; /^no_proxy=/d; /^HTTP_PROXY=/d; /^HTTPS_PROXY=/d; /^FTP_PROXY=/d; /^NO_PROXY=/d' /etc/environment || true
        fi
        echo ">>> Configuracoes de proxy removidas"
        ;;

    MANUAL)
        echo ">>> Configurando proxy manual: ${PROXY_HTTP}:${PROXY_PORTA}"

        # Construir URL do proxy
        if [ -n "$PROXY_URL" ] && [ "$PROXY_URL" != "" ]; then
            PROXY_FULL_URL="$PROXY_URL"
        else
            PROXY_FULL_URL="http://${PROXY_HTTP}:${PROXY_PORTA}"
        fi

        # Configurar APT
        cat > /etc/apt/apt.conf.d/95seederlinux-proxy <<EOF
Acquire::http::Proxy "${PROXY_FULL_URL}";
Acquire::https::Proxy "${PROXY_FULL_URL}";
Acquire::ftp::Proxy "${PROXY_FULL_URL}";
EOF

        # Configurar /etc/environment
        if [ -f /etc/environment ]; then
            # Remover entradas antigas
            sed -i '/^http_proxy=/d; /^https_proxy=/d; /^ftp_proxy=/d; /^no_proxy=/d; /^HTTP_PROXY=/d; /^HTTPS_PROXY=/d; /^FTP_PROXY=/d; /^NO_PROXY=/d' /etc/environment || true
        fi

        cat >> /etc/environment <<EOF
http_proxy="${PROXY_FULL_URL}"
https_proxy="${PROXY_FULL_URL}"
ftp_proxy="${PROXY_FULL_URL}"
HTTP_PROXY="${PROXY_FULL_URL}"
HTTPS_PROXY="${PROXY_FULL_URL}"
FTP_PROXY="${PROXY_FULL_URL}"
EOF

        if [ -n "$NO_PROXY" ] && [ "$NO_PROXY" != "" ]; then
            echo "no_proxy=\"${NO_PROXY}\"" >> /etc/environment
            echo "NO_PROXY=\"${NO_PROXY}\"" >> /etc/environment
        fi

        echo ">>> Proxy manual configurado"
        ;;

    PAC)
        echo ">>> Configurando proxy via PAC: ${PAC_URL}"

        if [ -z "$PAC_URL" ] || [ "$PAC_URL" = "" ]; then
            echo ">>> ERRO: PAC_URL nao definido para modo PAC"
            read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
            if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
                echo ">>> Instalacao abortada pelo usuario."
                exit 1
            fi
            echo ">>> Continuando apesar do erro..."
        fi

        # Configurar APT com PAC (apt suporta PAC via auto)
        cat > /etc/apt/apt.conf.d/95seederlinux-proxy <<EOF
Acquire::http::Proxy::Pac "${PAC_URL}";
Acquire::https::Proxy::Pac "${PAC_URL}";
EOF

        # Para navegadores, o PAC sera configurado no core_browser.sh
        echo "PAC_URL=${PAC_URL}" > /etc/seederlinux/pac_url.conf 2>/dev/null || {
            mkdir -p /etc/seederlinux
            echo "PAC_URL=${PAC_URL}" > /etc/seederlinux/pac_url.conf
        }

        echo ">>> Proxy via PAC configurado"
        ;;

    *)
        echo ">>> ERRO: Modo de proxy invalido: $PROXY_MODE"
        read -p ">>> Deseja continuar mesmo assim? (S/n): " CONTINUE
        if [[ "$CONTINUE" =~ ^[Nn]$ ]]; then
            echo ">>> Instalacao abortada pelo usuario."
            exit 1
        fi
        echo ">>> Continuando apesar do erro..."
        ;;
esac

echo ">>> [17] Proxy do sistema configurado!"
echo "============================================================"
$SeederScript$,
    TRUE,
    TRUE,
    17,
    1,
    NULL
) ON CONFLICT (filename) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    content = EXCLUDED.content,
    execution_order = EXCLUDED.execution_order,
    version = EXCLUDED.version,
    is_active = EXCLUDED.is_active,
    updated_at = CURRENT_TIMESTAMP;



-- ============================================================================
-- FIM: 19 scripts core inseridos.
-- Ordem de execucao:
--   01 core_dns.sh              (configura DNS ANTES de apt-get update)
--   02 core_repositories.sh     (agora tem DNS resolvendo)
--   03 core_packages.sh
--   04 core_domain.sh
--   05 core_browser.sh
--   06 core_inventory.sh
--   07 core_printers.sh
--   08 core_vnc.sh
--   09 core_conky.sh
--   10 core_apps.sh
--   11 core_legados.sh
--   12 core_config.sh
--   13 core_branding.sh
--   14 core_logon.sh
--   15 core_logoff.sh
--   16 core_session_{lightdm|gdm3|sddm}.sh   (bundle mantem apenas 1 conforme DISPLAY_MANAGER)
--   17 core_proxy.sh
-- ============================================================================
