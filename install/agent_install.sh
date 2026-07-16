#!/bin/bash
# ============================================================================
# SeederLinux Lite - Agent Installation Script
# ============================================================================
# Installs the SeederLinux agent on a Linux station.
#
# Usage:
#   sudo bash install/agent_install.sh
#
# What it does:
#   1. Copies agent.py to /usr/local/bin/seeder-agent
#   2. Creates /etc/seeder/ config directory
#   3. Creates /var/log/seeder/ log directory
#   4. Creates /var/cache/seeder/ cache directory
#   5. Adds a crontab entry to run every 15 minutes
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Erro: Execute como root (use sudo)${NC}"
    exit 1
fi

# Paths
AGENT_SRC="downloads/agent.py"
AGENT_DEST="/usr/local/bin/seeder-agent"
CONFIG_DIR="/etc/seeder"
LOG_DIR="/var/log/seeder"
CACHE_DIR="/var/cache/seeder"
BUNDLE_FILE="$CACHE_DIR/bundle.sh"
CONFIG_FILE="$CONFIG_DIR/agent.conf"
CRON_JOB="*/15 * * * * $AGENT_DEST >> $LOG_DIR/agent.log 2>&1"

echo "============================================"
echo "  SeederLinux Lite - Agent Installation"
echo "============================================"
echo ""

# Step 1: Copy agent
echo -e "${YELLOW}[1/5] Copiando agente...${NC}"
if [ ! -f "$AGENT_SRC" ]; then
    echo -e "${RED}Erro: $AGENT_SRC não encontrado${NC}"
    echo "Execute este script a partir do diretório raiz do projeto."
    exit 1
fi
cp "$AGENT_SRC" "$AGENT_DEST"
chmod 755 "$AGENT_DEST"
echo -e "${GREEN}  Agente instalado em $AGENT_DEST${NC}"

# Step 2: Create config directory
echo -e "${YELLOW}[2/5] Criando diretório de configuração...${NC}"
mkdir -p "$CONFIG_DIR"
chmod 750 "$CONFIG_DIR"

# Create config file if it doesn't exist
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" << 'EOF'
[server]
url = https://seederlinux.comara.intraer
EOF
    chmod 640 "$CONFIG_FILE"
    echo -e "${GREEN}  Configuração criada em $CONFIG_FILE${NC}"
else
    echo -e "${YELLOW}  Configuração já existe, mantendo${NC}"
fi

# Step 3: Create log directory
echo -e "${YELLOW}[3/5] Criando diretório de log...${NC}"
mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"
touch "$LOG_DIR/agent.log"
chmod 640 "$LOG_DIR/agent.log"
echo -e "${GREEN}  Log em $LOG_DIR/agent.log${NC}"

# Step 4: Create cache directory
echo -e "${YELLOW}[4/5] Criando diretório de cache...${NC}"
mkdir -p "$CACHE_DIR"
chmod 755 "$CACHE_DIR"
echo -e "${GREEN}  Cache em $CACHE_DIR${NC}"

# Step 5: Add crontab entry
echo -e "${YELLOW}[5/5] Configurando crontab...${NC}"
CRON_FILE="/etc/cron.d/seeder-agent"
cat > "$CRON_FILE" << EOF
# SeederLinux Lite Agent - runs every 15 minutes
$CRON_JOB
EOF
chmod 644 "$CRON_FILE"
echo -e "${GREEN}  Cron configurado em $CRON_FILE${NC}"

echo ""
echo "============================================"
echo -e "${GREEN}  Instalação concluída com sucesso!${NC}"
echo "============================================"
echo ""
echo "Próximos passos:"
echo "  1. Edite $CONFIG_FILE se o servidor for diferente"
echo ""
echo "  2. Primeiro run — vincule a estação à organização (--org obrigatório):"
echo "       sudo $AGENT_DEST --org <SIGLA_OM>"
echo "       Exemplo: sudo $AGENT_DEST --org COMARA"
echo ""
echo "  3. Após o primeiro run, o token é salvo automaticamente."
echo "     Runs subsequentes não precisam de --org:"
echo "       sudo $AGENT_DEST"
echo ""
echo "  4. Para testar sem executar bundle:"
echo "       sudo $AGENT_DEST --org COMARA --dry-run --verbose"
echo ""
echo "  5. O agente executará automaticamente a cada 15 minutos (cron)."
echo ""
echo "Arquivos:"
echo "  Config: $CONFIG_FILE"
echo "  Token:  $CONFIG_DIR/station_token  (gerado no primeiro run)"
echo "  Log:    $LOG_DIR/agent.log"
echo "  Cache:  $BUNDLE_FILE"
echo ""
