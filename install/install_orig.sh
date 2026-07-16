cd /opt/SeederLinuxLite_v3/install

# Crie o script corrigido
cat > install_fixed.sh << 'SCRIPTEOF'
#!/bin/bash
# ============================================================================
# SeederLinux Lite - Installation Script (Debian 13 Ready)
# ============================================================================


cat > /etc/apt/sources.list << 'EOF'
# Debian 13 (Trixie) - Repositórios Oficiais

# Repositório principal
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware

# Atualizações de segurança
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware

# Atualizações estáveis
deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
EOF

apt update



set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_NAME="seederlinux-lite"
INSTALL_DIR="/var/www/${PROJECT_NAME}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DB_NAME="seederlinux"
DB_USER="seeder"
DB_PASS="seeder123"

APACHE_USER="www-data"
APACHE_GROUP="www-data"
SERVER_NAME="localhost"

print_header() {
    echo -e "\n${CYAN}${BOLD}============================================================================${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${CYAN}${BOLD}============================================================================${NC}\n"
}

print_step()   { echo -e "${BLUE}[➤]${NC} $1"; }
print_success(){ echo -e "${GREEN}[✓]${NC} $1"; }
print_warning(){ echo -e "${YELLOW}[!]${NC} $1"; }
print_error()  { echo -e "${RED}[✗]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Execute como root: sudo $0"
        exit 1
    fi
}

install_system_packages() {
    print_header "ATUALIZANDO E INSTALANDO PACOTES DO SISTEMA"

    print_step "Atualizando lista de pacotes..."
    apt-get update -qq

    print_step "Instalando utilitários básicos..."
    apt-get install -y -qq curl wget git unzip ca-certificates apt-transport-https

    print_step "Instalando PostgreSQL..."
    apt-get install -y -qq postgresql postgresql-contrib

    print_step "Instalando PHP e extensões..."
    apt-get install -y -qq \
        php \
        php-cli \
        php-fpm \
        php-pgsql \
        php-mbstring \
        php-xml \
        php-curl \
        php-zip \
        php-gd \
        libapache2-mod-php

    PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "desconhecida")
    print_success "PHP ${PHP_VER} instalado"

    print_step "Instalando Apache2..."
    apt-get install -y -qq apache2

    print_step "Habilitando módulos do Apache..."
    a2enmod rewrite headers ssl proxy proxy_http

    print_success "Pacotes instalados com sucesso"
}

setup_postgresql() {
    print_header "CONFIGURANDO POSTGRESQL"

    print_step "Iniciando serviço PostgreSQL..."
    systemctl start postgresql
    systemctl enable postgresql

    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw ${DB_NAME}; then
        print_warning "Banco de dados '${DB_NAME}' já existe"
        read -p "Recriar banco? (s/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            print_step "Removendo banco existente..."
            sudo -u postgres dropdb --if-exists ${DB_NAME}
            sudo -u postgres dropuser --if-exists ${DB_USER}
        else
            print_step "Mantendo banco existente"
            return 0
        fi
    fi

    print_step "Criando usuário: ${DB_USER}"
    sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';" || true

    print_step "Criando banco: ${DB_NAME}"
    sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};"

    print_step "Concedendo privilégios..."
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"

    print_step "Testando conexão..."
    if PGPASSWORD=${DB_PASS} psql -h localhost -U ${DB_USER} -d ${DB_NAME} -c "SELECT 1;" > /dev/null 2>&1; then
        print_success "Conexão com PostgreSQL OK"
    else
        print_error "Falha ao conectar"
        exit 1
    fi
}

apply_database_schema() {
    print_header "APLICANDO SCHEMA DO BANCO DE DADOS"
    SCHEMA_FILE="${PROJECT_ROOT}/install/schema.sql"

    if [ ! -f "$SCHEMA_FILE" ]; then
        print_error "schema.sql não encontrado: $SCHEMA_FILE"
        exit 1
    fi

    print_step "Aplicando schema..."
    PGPASSWORD=${DB_PASS} psql -h localhost -U ${DB_USER} -d ${DB_NAME} -f "$SCHEMA_FILE"
    print_success "Schema aplicado"
}

setup_project_files() {
    print_header "CONFIGURANDO ARQUIVOS DO PROJETO"

    print_step "Criando diretório: ${INSTALL_DIR}"
    mkdir -p ${INSTALL_DIR}

    print_step "Copiando arquivos do projeto..."
    cp -r ${PROJECT_ROOT}/* ${INSTALL_DIR}/

    mkdir -p ${INSTALL_DIR}/downloads

    print_step "Criando .env..."
    cat > ${INSTALL_DIR}/.env <<EOF
DB_HOST=localhost
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
APP_NAME=SeederLinux Lite
APP_ENV=production
APP_DEBUG=false
EOF

    print_success "Arquivos configurados"
}

setup_permissions() {
    print_header "CONFIGURANDO PERMISSÕES"

    print_step "Ajustando proprietário..."
    chown -R ${APACHE_USER}:${APACHE_GROUP} ${INSTALL_DIR}

    print_step "Permissões de diretórios..."
    find ${INSTALL_DIR} -type d -exec chmod 755 {} \;
    print_step "Permissões de arquivos..."
    find ${INSTALL_DIR} -type f -exec chmod 644 {} \;

    chmod +x ${INSTALL_DIR}/downloads/*.py 2>/dev/null || true
    chmod +x ${INSTALL_DIR}/scripts/*.sh 2>/dev/null || true

    mkdir -p ${INSTALL_DIR}/storage/logs
    chmod -R 775 ${INSTALL_DIR}/storage

    chmod 600 ${INSTALL_DIR}/.env
    print_success "Permissões configuradas"
}

configure_apache() {
    print_header "CONFIGURANDO APACHE"

    print_step "Criando VirtualHost..."
cat > /etc/apache2/sites-available/${PROJECT_NAME}.conf <<EOF

<VirtualHost *:80>
    ServerName ${SERVER_NAME}

    RewriteEngine On
    RewriteCond %{HTTPS} !=on
    RewriteRule ^/?(.*) https://%{SERVER_NAME}/\$1 [R=301,L]
</VirtualHost>

<VirtualHost *:443>
    ServerName ${SERVER_NAME}

    DocumentRoot ${INSTALL_DIR}/public

    SSLEngine on
    SSLCertificateFile /etc/ssl/seederlinux-lite/seederlinux-lite.crt
    SSLCertificateKeyFile /etc/ssl/seederlinux-lite/seederlinux-lite.key

    <Directory ${INSTALL_DIR}/public>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${PROJECT_NAME}_error.log
    CustomLog \${APACHE_LOG_DIR}/${PROJECT_NAME}_access.log combined

    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
</VirtualHost>

EOF

    a2dissite 000-default.conf || true
    a2ensite ${PROJECT_NAME}.conf

    print_step "Testando configuração do Apache..."
    if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
        print_success "Configuração OK"
    else
        print_error "Erro na configuração"
        apache2ctl configtest
        exit 1
    fi

    print_step "Reiniciando Apache..."
    systemctl restart apache2
    systemctl enable apache2

    print_success "Apache configurado"
}

show_summary() {
    print_header "INSTALAÇÃO CONCLUÍDA"

    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║           SEEDERLINUX LITE - INSTALAÇÃO COMPLETA               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    echo -e "\n${BOLD}Acesso:${NC}"
    echo -e "  http://${SERVER_NAME}/"
    echo -e "\n${BOLD}Banco de Dados:${NC}"
    echo -e "  Database: ${DB_NAME}"
    echo -e "  User: ${DB_USER}"
    echo -e "  Pass: ${DB_PASS}"
    echo -e "\n${YELLOW}${BOLD}⚠ ALTERE AS SENHAS PADRÃO!${NC}\n"
}

main() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║       SEEDEALINUX LITE - INSTALAÇÃO v1.0.0 (Debian 13)        ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}\n"

    check_root

    echo -e "${YELLOW}Este script irá:${NC}"
    echo "  • Instalar Apache2, PHP, PostgreSQL"
    echo "  • Criar banco e usuário"
    echo "  • Configurar VirtualHost"
    echo "  • Copiar arquivos para ${INSTALL_DIR}"
    echo ""
    read -p "Deseja continuar? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        echo "Instalação cancelada."
        exit 0
    fi

    install_system_packages
    setup_postgresql
    apply_database_schema
    setup_project_files
    setup_permissions
    configure_apache
    show_summary
}

main "$@"
SCRIPTEOF

# Torne executável
chmod +x install_fixed.sh

# Execute
./install_fixed.sh