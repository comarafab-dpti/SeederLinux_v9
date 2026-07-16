-- ============================================================================
-- SeederLinux Lite - Complete Database Schema
-- Self-contained, idempotent, creates everything from scratch
-- PostgreSQL 14+ / Supabase
-- ============================================================================

-- ============================================================================
-- Table: users
-- Purpose: Store admin users for the panel
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    full_name VARCHAR(150),
    role VARCHAR(20) DEFAULT 'admin_gap',
    is_active BOOLEAN DEFAULT TRUE,
    organization_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Table: organizations
-- Purpose: Store military organizations (OMs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS organizations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    acronym VARCHAR(20) UNIQUE NOT NULL,
    domain VARCHAR(100),
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    serial_config INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Add foreign key constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'users_organization_id_fkey'
        AND table_name = 'users'
    ) THEN
        ALTER TABLE users ADD CONSTRAINT users_organization_id_fkey
        FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL;
    END IF;
END $$;

-- ============================================================================
-- Table: variable_definitions
-- ============================================================================
CREATE TABLE IF NOT EXISTS variable_definitions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) UNIQUE NOT NULL,
    placeholder VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    default_value TEXT,
    category VARCHAR(50) DEFAULT 'general',
    type VARCHAR(20) DEFAULT 'string',
    is_required BOOLEAN DEFAULT TRUE,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Table: organization_variables
-- ============================================================================
CREATE TABLE IF NOT EXISTS organization_variables (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    variable_id INTEGER NOT NULL REFERENCES variable_definitions(id) ON DELETE CASCADE,
    value TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(organization_id, variable_id)
);

-- ============================================================================
-- Table: scripts
-- ============================================================================
CREATE TABLE IF NOT EXISTS scripts (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    filename VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    content TEXT NOT NULL,
    is_core BOOLEAN DEFAULT FALSE,
    execution_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    version INTEGER DEFAULT 1,
    organization_id INTEGER REFERENCES organizations(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Table: deploy_bundles
-- ============================================================================
CREATE TABLE IF NOT EXISTS deploy_bundles (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    filename VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    script_ids TEXT,
    scripts_count INTEGER DEFAULT 0,
    generated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Table: script_executions
-- ============================================================================
CREATE TABLE IF NOT EXISTS script_executions (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER REFERENCES organizations(id) ON DELETE SET NULL,
    script_filename VARCHAR(100),
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    execution_ip VARCHAR(45),
    status VARCHAR(20) DEFAULT 'pending',
    output TEXT,
    agent_version VARCHAR(20)
);

-- ============================================================================
-- Table: activity_log
-- ============================================================================
CREATE TABLE IF NOT EXISTS activity_log (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL,
    target VARCHAR(100),
    target_id INTEGER,
    details TEXT,
    organization_id INTEGER REFERENCES organizations(id) ON DELETE SET NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    session_id VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Table: audit_events
-- ============================================================================
CREATE TABLE IF NOT EXISTS audit_events (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER REFERENCES organizations(id) ON DELETE SET NULL,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    entity VARCHAR(50) NOT NULL,
    entity_id INTEGER,
    action VARCHAR(50) NOT NULL,
    details JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Table: stations
-- ============================================================================
CREATE TABLE IF NOT EXISTS stations (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER REFERENCES organizations(id) ON DELETE SET NULL,
    hostname VARCHAR(200),
    serial_number VARCHAR(100),
    os_name VARCHAR(100),
    os_version VARCHAR(100),
    ip_address VARCHAR(45),
    mac_address VARCHAR(17),
    last_checkin TIMESTAMP,
    status VARCHAR(20) DEFAULT 'never_connected',
    configuration_serial INTEGER DEFAULT 0,
    token TEXT UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Table: system_settings
-- ============================================================================
CREATE TABLE IF NOT EXISTS system_settings (
    id SERIAL PRIMARY KEY,
    key VARCHAR(100) UNIQUE NOT NULL,
    value TEXT,
    value_type VARCHAR(20) DEFAULT 'string',
    description TEXT,
    is_public BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL
);

-- ============================================================================
-- Create indexes
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_org_vars_org ON organization_variables(organization_id);
CREATE INDEX IF NOT EXISTS idx_org_vars_var ON organization_variables(variable_id);
CREATE INDEX IF NOT EXISTS idx_scripts_filename ON scripts(filename);
CREATE INDEX IF NOT EXISTS idx_scripts_core ON scripts(is_core, execution_order);
CREATE INDEX IF NOT EXISTS idx_scripts_org ON scripts(organization_id);
CREATE INDEX IF NOT EXISTS idx_exec_org ON script_executions(organization_id);
CREATE INDEX IF NOT EXISTS idx_exec_date ON script_executions(executed_at);
CREATE INDEX IF NOT EXISTS idx_exec_status ON script_executions(status);
CREATE INDEX IF NOT EXISTS idx_activity_user ON activity_log(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_action ON activity_log(action);
CREATE INDEX IF NOT EXISTS idx_activity_target ON activity_log(target, target_id);
CREATE INDEX IF NOT EXISTS idx_activity_date ON activity_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_org ON activity_log(organization_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_org ON audit_events(organization_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_user ON audit_events(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_entity ON audit_events(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_date ON audit_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_deploy_bundles_org ON deploy_bundles(organization_id);
CREATE INDEX IF NOT EXISTS idx_deploy_bundles_date ON deploy_bundles(generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_stations_org ON stations(organization_id);
CREATE INDEX IF NOT EXISTS idx_stations_token ON stations(token);
CREATE INDEX IF NOT EXISTS idx_stations_status ON stations(status);
CREATE INDEX IF NOT EXISTS idx_stations_checkin ON stations(last_checkin DESC);

-- ============================================================================
-- Create views
-- ============================================================================
CREATE OR REPLACE VIEW v_organization_variables AS
SELECT
    o.id AS org_id,
    o.acronym AS org_acronym,
    o.name AS org_name,
    vd.id AS var_id,
    vd.name AS var_name,
    vd.placeholder,
    vd.description,
    vd.category,
    vd.default_value,
    COALESCE(ov.value, vd.default_value) AS current_value
FROM organizations o
CROSS JOIN variable_definitions vd
LEFT JOIN organization_variables ov ON ov.organization_id = o.id AND ov.variable_id = vd.id
WHERE o.is_active = TRUE
ORDER BY vd.display_order;

-- ============================================================================
-- Insert default admin user (password: admin123)
-- ============================================================================
INSERT INTO users (username, password_hash, email, full_name, role, is_active)
VALUES ('admin', '$2y$12$aclfbpmKYX0DoMcu8EmQeO1xyziOBv9/WjuWR6y3/ovgF74QTaLhC', 'admin@seeder.local', 'Administrator', 'admin_gap', TRUE)
ON CONFLICT (username) DO NOTHING;

-- ============================================================================
-- Insert sample organization
-- ============================================================================
INSERT INTO organizations (name, acronym, domain, description)
VALUES ('Comando da Comara', 'COMARA', 'comara.intraer', 'Comando do Comando da Aeronáutica de Brasília')
ON CONFLICT (acronym) DO NOTHING;

-- ============================================================================
-- Insert standard variable definitions
-- ============================================================================
INSERT INTO variable_definitions (name, placeholder, description, default_value, category, is_required, display_order) VALUES
-- Domain Configuration
('DOMINIO', '{{DOMINIO}}', 'Domínio AD completo', 'comara.intraer', 'dominio', TRUE, 1),
('DOMINIO_NETBIOS', '{{DOMINIO_NETBIOS}}', 'Nome NetBIOS do domínio', 'COMARA', 'dominio', TRUE, 2),
('DC_IP', '{{DC_IP}}', 'IP do Controlador de Domínio', '10.108.64.51', 'dominio', TRUE, 3),
('DNS_INTERNET', '{{DNS_INTERNET}}', 'DNS para internet (fallback)', '10.108.64.27', 'rede', TRUE, 4),
('DNS_PRIMARIO', '{{DNS_PRIMARIO}}', 'DNS primário para resolução de nomes', '10.108.64.51', 'dominio', TRUE, 20),
('DNS_SECUNDARIO', '{{DNS_SECUNDARIO}}', 'DNS secundário (fallback)', '10.108.64.27', 'dominio', FALSE, 21),
('NTP_SERVER', '{{NTP_SERVER}}', 'Servidor NTP para sincronização de horário', '10.108.64.51', 'dominio', FALSE, 22),
('OU_PADRAO', '{{OU_PADRAO}}', 'Unidade Organizacional padrão no AD', 'OU=Estacoes,DC=comara,DC=intraer', 'dominio', FALSE, 23),
('GRUPO_ADMIN', '{{GRUPO_ADMIN}}', 'Grupo administrador do domínio', 'Domain Admins', 'dominio', TRUE, 24),
('OFFLINE_AUTH_ENABLED', '{{OFFLINE_AUTH_ENABLED}}', 'Habilitar autenticação offline', 'true', 'dominio', FALSE, 25),
('OFFLINE_AUTH_DAYS', '{{OFFLINE_AUTH_DAYS}}', 'Dias para cache de credenciais offline', '30', 'dominio', FALSE, 26),
-- Repository URLs
('BASE_URL', '{{BASE_URL}}', 'URL base do repositório de scripts', 'https://softwarelivre.comara.intraer', 'rede', TRUE, 5),
-- OCS Inventory Configuration
('OCS_SERVER', '{{OCS_SERVER}}', 'Servidor OCS Inventory', 'http://ocs.comara.intraer/ocsinventory', 'inventario', TRUE, 6),
('OCS_TAG', '{{OCS_TAG}}', 'Tag OCS da organização', 'GAPBE-COMARA', 'inventario', TRUE, 7),
('GLPI_SERVER', '{{GLPI_SERVER}}', 'Servidor GLPI para inventário', '', 'inventario', FALSE, 60),
('INVENTORY_ENABLED', '{{INVENTORY_ENABLED}}', 'Habilitar inventário automático', 'true', 'inventario', FALSE, 61),
-- Print Server
('PRINT_SERVER', '{{PRINT_SERVER}}', 'Servidor de impressão', '10.108.64.20', 'rede', FALSE, 8),
('DEFAULT_PRINTER', '{{DEFAULT_PRINTER}}', 'Impressora padrão', '', 'impressoras', FALSE, 80),
('PRINTERS', '{{PRINTERS}}', 'Lista de impressoras (separadas por vírgula)', '', 'impressoras', FALSE, 81),
-- Proxy Configuration
('PROXY_HTTP', '{{PROXY_HTTP}}', 'Proxy HTTP corporativo', '10.108.88.4', 'proxy', FALSE, 9),
('PROXY_PORTA', '{{PROXY_PORTA}}', 'Porta do proxy', '8080', 'proxy', FALSE, 10),
('PROXY_URL', '{{PROXY_URL}}', 'URL completa do proxy', 'http://proxy.comara.intraer:8080', 'proxy', FALSE, 11),
('PROXY_MODE', '{{PROXY_MODE}}', 'Modo de proxy: NONE, MANUAL, PAC', 'MANUAL', 'navegador', FALSE, 40),
('PAC_URL', '{{PAC_URL}}', 'URL do arquivo PAC (Proxy Auto-Config)', '', 'navegador', FALSE, 41),
('NO_PROXY', '{{NO_PROXY}}', 'Lista de exceções de proxy (separadas por vírgula)', 'localhost,127.0.0.1,comara.intraer', 'navegador', FALSE, 42),
-- Browser Configuration
('HOMEPAGE', '{{HOMEPAGE}}', 'Página inicial do portal', 'www.comara.intraer', 'navegador', FALSE, 12),
-- Admin Groups
('GRUPO_ADMIN_AD', '{{GRUPO_ADMIN_AD}}', 'Grupo admin no AD para sudo', 'Dominio Admins', 'seguranca', TRUE, 13),
('GRUPO_ADMIN_LINUX', '{{GRUPO_ADMIN_LINUX}}', 'Grupo local para sudo', 'linux-admins', 'seguranca', TRUE, 14),
('GRUPO_DASTI', '{{GRUPO_DASTI}}', 'Grupo DASTI para sudo', '_DASTI', 'seguranca', FALSE, 15),
-- Branding
('OM_ACRONYM', '{{OM_ACRONYM}}', 'Sigla da Organização Militar', '', 'branding', FALSE, 18),
('WALLPAPER_URL', '{{WALLPAPER_URL}}', 'URL do wallpaper da OM', 'https://softwarelivre.comara.intraer/wallpapers/comara.jpg', 'branding', FALSE, 16),
('LOGO_URL', '{{LOGO_URL}}', 'URL do logo da OM', 'https://softwarelivre.comara.intraer/logos/comara.png', 'branding', FALSE, 17),
('DISPLAY_NAME', '{{DISPLAY_NAME}}', 'Nome de exibição da OM', 'Comando da Comara', 'branding', FALSE, 50),
('WALLPAPER_LOGIN_URL', '{{WALLPAPER_LOGIN_URL}}', 'URL do wallpaper da tela de login', '', 'branding', FALSE, 51),
('GREETER_URL', '{{GREETER_URL}}', 'URL do greeter personalizado', '', 'branding', FALSE, 52),
('THEME', '{{THEME}}', 'Tema GTK a ser aplicado', 'Adwaita', 'branding', FALSE, 53),
('CONKY_PROFILE', '{{CONKY_PROFILE}}', 'Perfil do Conky para monitoração', 'default', 'branding', FALSE, 54),
-- Arquivos
('SERVIDOR_ARQUIVOS', '{{SERVIDOR_ARQUIVOS}}', 'Servidor de arquivos (SMB/NFS)', '10.108.64.20', 'arquivos', FALSE, 30),
('COMPARTILHAMENTOS', '{{COMPARTILHAMENTOS}}', 'Lista de compartilhamentos (separados por vírgula)', 'publico,usuarios,setores', 'arquivos', FALSE, 31),
('MOUNT_BASE', '{{MOUNT_BASE}}', 'Base de montagem para compartilhamentos', '/mnt/servidor', 'arquivos', FALSE, 32),
-- Acesso Remoto
('REMOTE_METHOD', '{{REMOTE_METHOD}}', 'Método de acesso remoto (ssh, xrdp, anydesk)', 'ssh', 'acesso_remoto', FALSE, 70),
('REMOTE_SERVER', '{{REMOTE_SERVER}}', 'Servidor de acesso remoto', '', 'acesso_remoto', FALSE, 71),
-- Certificados
('CERTIFICATE_BUNDLE', '{{CERTIFICATE_BUNDLE}}', 'URL do bundle de certificados CA', '', 'certificados', FALSE, 90),
('CERTIFICATE_AUTO_INSTALL', '{{CERTIFICATE_AUTO_INSTALL}}', 'Instalar certificados automaticamente', 'true', 'certificados', FALSE, 91),
-- Repositórios
('REPOSITORY_MODE', '{{REPOSITORY_MODE}}', 'Modo de repositório: PUBLIC, MIRROR, HYBRID, CUSTOM', 'MIRROR', 'repositorios', TRUE, 100),
('REPOSITORY_URL', '{{REPOSITORY_URL}}', 'URL do repositório espelho', 'https://softwarelivre.comara.intraer', 'repositorios', FALSE, 101),
('REPOSITORY_FALLBACK', '{{REPOSITORY_FALLBACK}}', 'URL de repositório fallback (internet)', 'http://deb.debian.org/debian', 'repositorios', FALSE, 102)
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- Insert default variable values for organization ID=1 (COMARA)
-- ============================================================================
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT 1, vd.id, vd.default_value
FROM variable_definitions vd
WHERE NOT EXISTS (
    SELECT 1 FROM organization_variables ov
    WHERE ov.organization_id = 1 AND ov.variable_id = vd.id
)
AND vd.default_value IS NOT NULL AND vd.default_value != '';

-- Set OM_ACRONYM value for org 1
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT 1, vd.id, 'COMARA'
FROM variable_definitions vd
WHERE vd.name = 'OM_ACRONYM'
AND NOT EXISTS (
    SELECT 1 FROM organization_variables ov
    WHERE ov.organization_id = 1 AND ov.variable_id = vd.id
);

-- ============================================================================
-- Insert core scripts
-- ============================================================================
INSERT INTO scripts (name, filename, description, content, is_core, execution_order) VALUES
-- Core Script 1: Network Configuration
('Configuração de Rede', 'core_network.sh',
'Gerencia configurações de rede, incluindo proxy, página inicial do navegador e servidor de impressão',
'#!/bin/bash
set -e
echo "============================================================"
echo "CONFIGURANDO REDE E PROXY"
echo "============================================================"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
HOMEPAGE="{{HOMEPAGE}}"
PRINT_SERVER="{{PRINT_SERVER}}"
DNS_INTERNET="{{DNS_INTERNET}}"
echo ">>> Configurando DNS..."
if [ -f /etc/resolv.conf ]; then
    sudo cp /etc/resolv.conf /etc/resolv.conf.bak
fi
if [ -n "$PROXY_HTTP" ] && [ "$PROXY_HTTP" != " " ]; then
    echo ">>> Configurando proxy HTTP: $PROXY_HTTP:$PROXY_PORTA"
    export http_proxy="http://$PROXY_HTTP:$PROXY_PORTA"
    export https_proxy="http://$PROXY_HTTP:$PROXY_PORTA"
    export HTTP_PROXY="http://$PROXY_HTTP:$PROXY_PORTA"
    export HTTPS_PROXY="http://$PROXY_HTTP:$PROXY_PORTA"
    export no_proxy="localhost,127.0.0.1,{{DOMINIO}}"
    echo "http_proxy=\"http://$PROXY_HTTP:$PROXY_PORTA\"" | sudo tee -a /etc/environment
    echo "https_proxy=\"http://$PROXY_HTTP:$PROXY_PORTA\"" | sudo tee -a /etc/environment
    echo "no_proxy=\"localhost,127.0.0.1,{{DOMINIO}}\"" | sudo tee -a /etc/environment
fi
echo ">>> Configurando página inicial do navegador..."
if [ -d /usr/lib/firefox ]; then
    sudo tee /usr/lib/firefox/defaults/pref/autoconfig.js > /dev/null <<EOF
pref("general.config.filename", "mozilla.cfg");
pref("general.config.obscure_value", 0);
EOF
    sudo tee /usr/lib/firefox/mozilla.cfg > /dev/null <<EOF
//
lockPref("browser.startup.homepage", "http://$HOMEPAGE");
lockPref("startup.homepage_welcome_url", "http://$HOMEPAGE");
lockPref("browser.startup.page", 1);
EOF
fi
if command -v lpadmin &> /dev/null; then
    echo ">>> Configurando servidor de impressão..."
    if [ -n "$PRINT_SERVER" ] && [ "$PRINT_SERVER" != " " ]; then
        sudo lpadmin -p ImpressoraPadrao -E -v ipp://$PRINT_SERVER:631/printers/ImpressoraPadrao -m everywhere
    fi
fi
echo ">>> Configuração de rede concluída!"
echo "============================================================"',
TRUE, 1),

-- Core Script 2: Domain Join
('Ingresso em Domínio AD', 'core_domain.sh',
'Responsável pelo ingresso da estação no Active Directory',
'#!/bin/bash
set -e
echo "============================================================"
echo "CONFIGURANDO DOMÍNIO E AUTENTICAÇÃO"
echo "============================================================"
DOMINIO="{{DOMINIO}}"
DOMINIO_NETBIOS="{{DOMINIO_NETBIOS}}"
DC_IP="{{DC_IP}}"
DNS_INTERNET="{{DNS_INTERNET}}"
GRUPO_ADMIN_AD="{{GRUPO_ADMIN_AD}}"
GRUPO_ADMIN_LINUX="{{GRUPO_ADMIN_LINUX}}"
GRUPO_DASTI="{{GRUPO_DASTI}}"
echo ">>> Domínio: $DOMINIO ($DOMINIO_NETBIOS)"
echo ">>> Controlador: $DC_IP"
CURRENT_HOSTNAME=$(hostname)
echo ">>> Hostname atual: $CURRENT_HOSTNAME"
echo ">>> Instalando pacotes de autenticacao..."
sudo apt-get update -qq
sudo apt-get install -y -qq sssd sssd-ad adcli realmd krb5-user packagekit
echo ">>> Configurando DNS para dominio..."
sudo cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
echo ">>> Preparando ingresso no domínio..."
sudo realm discover "$DOMINIO" || echo "Aviso: Não foi possível descobrir o realm via DNS"
echo ">>> Ingressando no dominio..."
sudo realm join "$DOMINIO" --user=admin || {
    echo "Tentando ingresso com usuario especifico..."
    sudo realm join "$DOMINIO" --user=Administrator
}
echo ">>> Configurando SSSD..."
sudo tee /etc/sssd/sssd.conf > /dev/null <<SSSDEOF
[sssd]
domains = $DOMINIO
services = nss, pam

[domain/$DOMINIO]
ad_domain = $DOMINIO
ad_server = $DC_IP
ad_hostname = $(hostname).$DOMINIO
krb5_realm = $(echo $DOMINIO | tr "[:lower:]" "[:upper:]")
realmd_tags = manages-system joined-with-adcli
cache_credentials = True
id_provider = ad
auth_provider = ad
chpass_provider = ad
access_provider = ad
ldap_id_mapping = True
use_fully_qualified_names = False
fallback_homedir = /home/%u@%d
simple_allow_groups = $GRUPO_ADMIN_AD, $GRUPO_ADMIN_LINUX, $GRUPO_DASTI
dyndns_update = True
dyndns_refresh_interval = 43200
dyndns_update_ptr = True
SSSDEOF
sudo chmod 600 /etc/sssd/sssd.conf
sudo systemctl enable sssd
sudo systemctl restart sssd
echo ">>> Configurando sudoers para grupos do domínio..."
sudo tee /etc/sudoers.d/domain_admins > /dev/null <<SUDOEOF
%$GRUPO_ADMIN_AD ALL=(ALL) ALL
%$GRUPO_ADMIN_LINUX ALL=(ALL) ALL
%$GRUPO_DASTI ALL=(ALL) NOPASSWD: ALL
SUDOEOF
sudo chmod 440 /etc/sudoers.d/domain_admins
echo ">>> Configurando PAM para criação automática de home..."
sudo sed -i "/^[^#]*pam_mkhomedir.so/s/^#//" /etc/pam.d/common-session
echo "session required pam_mkhomedir.so skel=/etc/skel/ umask=0077" | sudo tee -a /etc/pam.d/common-session
echo ">>> Verificando conexao com dominio..."
id admin@${DOMINIO,,} 2>/dev/null || echo "Aviso: Não foi possível verificar o usuario admin"
echo ">>> Configuração de domínio concluída!"
echo "============================================================"',
TRUE, 2),

-- Core Script 3: Inventory Agent
('Agente de Inventário OCS', 'core_inventory.sh',
'Configura o agente OCS Inventory para coleta de informações da estação',
'#!/bin/bash
set -e
echo "============================================================"
echo "CONFIGURANDO AGENTE OCS INVENTORY"
echo "============================================================"
OCS_SERVER="{{OCS_SERVER}}"
OCS_TAG="{{OCS_TAG}}"
DOMINIO="{{DOMINIO}}"
echo ">>> Servidor OCS: $OCS_SERVER"
echo ">>> Tag: $OCS_TAG"
echo ">>> Instalando dependencias..."
sudo apt-get update -qq
sudo apt-get install -y -qq ocsinventory-agent
sudo mkdir -p /etc/ocsinventory-agent
echo ">>> Criando configuração do agente..."
sudo tee /etc/ocsinventory-agent/ocsinventory-agent.cfg > /dev/null <<OCSEOF
server=$OCS_SERVER
tag=$OCS_TAG
ca=/etc/ssl/certs/ca-certificates.crt
basepackage=none
debug=0
OCSEOF
sudo tee /etc/cron.daily/ocsinventory-agent > /dev/null <<CRONEOF
#!/bin/bash
/usr/bin/ocsinventory-agent --force --nosoftware --tag="$OCS_TAG" --server="$OCS_SERVER"
CRONEOF
sudo chmod 755 /etc/cron.daily/ocsinventory-agent
echo ">>> Executando primeira inventariação..."
sudo /usr/bin/ocsinventory-agent --force --tag="$OCS_TAG" --server="$OCS_SERVER" || {
    echo "Aviso: Primeira inventariação pode ter falhado."
}
echo ">>> Agente OCS Inventory configurado com sucesso!"
echo "============================================================"',
TRUE, 3),

-- Core Script 4: Branding
('Branding e Identidade Visual', 'core_branding.sh',
'Aplica configurações de identidade visual, como wallpaper e tema',
'#!/bin/bash
set -e
echo "============================================================"
echo "CONFIGURANDO BRANDING E IDENTIDADE VISUAL"
echo "============================================================"
OM_ACRONYM="{{OM_ACRONYM}}"
WALLPAPER_URL="{{WALLPAPER_URL}}"
LOGO_URL="{{LOGO_URL}}"
PROXY_HTTP="{{PROXY_HTTP}}"
PROXY_PORTA="{{PROXY_PORTA}}"
echo ">>> OM: $OM_ACRONYM"
sudo mkdir -p /usr/share/backgrounds/seederlinux
sudo mkdir -p /usr/share/pixmaps/seederlinux
if [ -n "$WALLPAPER_URL" ] && [ "$WALLPAPER_URL" != " " ]; then
    echo ">>> Baixando wallpaper..."
    if [ -n "$PROXY_HTTP" ] && [ "$PROXY_HTTP" != " " ]; then
        export http_proxy="http://$PROXY_HTTP:$PROXY_PORTA"
        export https_proxy="http://$PROXY_HTTP:$PROXY_PORTA"
    fi
    wget -q -O /tmp/wallpaper.jpg "$WALLPAPER_URL" 2>/dev/null || {
        echo "Aviso: Não foi possível baixar o wallpaper."
    }
    if [ -f /tmp/wallpaper.jpg ]; then
        sudo cp /tmp/wallpaper.jpg /usr/share/backgrounds/seederlinux/wallpaper.jpg
        sudo ln -sf /usr/share/backgrounds/seederlinux/wallpaper.jpg /usr/share/backgrounds/default.jpg
    fi
fi
if [ -n "$LOGO_URL" ] && [ "$LOGO_URL" != " " ]; then
    echo ">>> Baixando logo..."
    wget -q -O /tmp/logo.png "$LOGO_URL" 2>/dev/null || true
    if [ -f /tmp/logo.png ]; then
        sudo cp /tmp/logo.png /usr/share/pixmaps/seederlinux/logo.png
    fi
fi
if [ -f /etc/lightdm/lightdm-gtk-greeter.conf ]; then
    echo ">>> Configurando LightDM..."
    sudo sed -i "s|^background=.*|background=/usr/share/backgrounds/seederlinux/wallpaper.jpg|" /etc/lightdm/lightdm-gtk-greeter.conf || true
fi
if command -v xfconf-query &> /dev/null; then
    echo ">>> Configurando wallpaper XFCE4..."
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s /usr/share/backgrounds/seederlinux/wallpaper.jpg 2>/dev/null || true
fi
sudo tee /etc/seederlinux-identity > /dev/null <<EOF
# SeederLinux Lite - Sistema Provisionado
# Organização: $OM_ACRONYM
# Data: $(date "+%Y-%m-%d %H:%M:%S")
# Hostname: $(hostname)
EOF
echo ">>> Branding configurado com sucesso!"
echo "============================================================"',
TRUE, 4)
ON CONFLICT (filename) DO NOTHING;

-- ============================================================================
-- Insert default system settings
-- ============================================================================
INSERT INTO system_settings (key, value, value_type, description, is_public) VALUES
('app_name', 'SeederLinux Lite', 'string', 'Nome da aplicação', TRUE),
('app_version', '1.0.0', 'string', 'Versão do sistema', TRUE),
('require_https', 'false', 'boolean', 'Requer HTTPS para acesso', FALSE),
('max_login_attempts', '5', 'integer', 'Máximo de tentativas de login', FALSE),
('login_lockout_minutes', '15', 'integer', 'Minutos de bloqueio após tentativas', FALSE),
('session_timeout', '86400', 'integer', 'Timeout de sessão em segundos', FALSE),
('bundle_retention_days', '30', 'integer', 'Dias para reter bundles gerados', FALSE),
('max_bundle_downloads', '100', 'integer', 'Máximo de downloads por hora por OM', FALSE),
('enable_activity_log', 'true', 'boolean', 'Habilitar log de atividades', FALSE),
('default_timezone', 'America/Sao_Paulo', 'string', 'Fuso horário padrão', TRUE)
ON CONFLICT (key) DO NOTHING;