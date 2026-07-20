#!/bin/bash
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
