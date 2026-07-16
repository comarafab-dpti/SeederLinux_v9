#!/bin/bash
# ============================================================================
# Core Script: core_inventory.sh
# SeederLinux Lite - OCS Inventory Agent
# ============================================================================
# Instala e configura o agente do OCS Inventory para coleta de inventario
# automatica da estacao.
# Os placeholders {{VARIAVEL}} são substituídos automaticamente
# pelo sistema na geração do bundle.
# ============================================================================

set -e

echo "============================================================"
echo "07 - Configurar OCS Inventory Agent"
echo "============================================================"

# ============================================================
# Variáveis
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
    echo ">>> [07] OCS Inventory desativado."
    echo "============================================================"
    exit 0
fi

if [ -z "$OCS_SERVER" ] || [ "$OCS_SERVER" = "" ]; then
    echo ">>> AVISO: OCS_SERVER nao definido. Pulando configuracao."
    echo ">>> [07] OCS Inventory nao configurado (servidor ausente)."
    echo "============================================================"
    exit 0
fi

echo ">>> Servidor OCS: $OCS_SERVER"
echo ">>> Tag OCS: $OCS_TAG"

# ============================================================
# Instalar pacotes do OCS Inventory
# ============================================================
echo ">>> Instalando agente OCS Inventory..."
export DEBIAN_FRONTEND=noninteractive
apt-get install -y ocsinventory-agent dmidecode

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

    # Instalar GLPI Agent se disponivel
    apt-get install -y glpi-agent 2>/dev/null || {
        echo ">>> GLPI Agent nao disponivel nos repositorios. Pulando."
    }
fi

# ============================================================
# Execucao inicial do inventario
# ============================================================
echo ">>> Executando coleta inicial de inventario..."
ocsinventory-agent --server="$OCS_SERVER" --tag="$OCS_TAG" --lazy 2>/dev/null || {
    echo ">>> AVISO: Falha na coleta inicial. Sera refeito via cron."
}

echo ">>> [07] OCS Inventory configurado!"
echo "============================================================"
