-- ============================================================================
-- SeederLinux Lite - Schema Update v2
-- Adds: stations table, serial_config column, extended variable catalog
-- Run AFTER schema.sql and schema_update.sql
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add serial_config to organizations (incremented when config changes)
-- ---------------------------------------------------------------------------
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS serial_config INTEGER DEFAULT 1;

-- ---------------------------------------------------------------------------
-- 2. Table: stations (inventory of provisioned machines)
-- ---------------------------------------------------------------------------
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

CREATE INDEX IF NOT EXISTS idx_stations_org ON stations(organization_id);
CREATE INDEX IF NOT EXISTS idx_stations_token ON stations(token);
CREATE INDEX IF NOT EXISTS idx_stations_status ON stations(status);
CREATE INDEX IF NOT EXISTS idx_stations_checkin ON stations(last_checkin DESC);

-- ---------------------------------------------------------------------------
-- 3. Extended variable catalog (new categories: arquivos, certificados, repositorios, acesso_remoto)
--    Uses INSERT ... ON CONFLICT to be idempotent
-- ---------------------------------------------------------------------------
INSERT INTO variable_definitions (name, placeholder, description, default_value, category, is_required, display_order)
VALUES
    -- Dominio (extended)
    ('DNS_PRIMARIO', '{{DNS_PRIMARIO}}', 'DNS primário para resolução de nomes', '10.108.64.51', 'dominio', TRUE, 20),
    ('DNS_SECUNDARIO', '{{DNS_SECUNDARIO}}', 'DNS secundário (fallback)', '10.108.64.27', 'dominio', FALSE, 21),
    ('NTP_SERVER', '{{NTP_SERVER}}', 'Servidor NTP para sincronização de horário', '10.108.64.51', 'dominio', FALSE, 22),
    ('OU_PADRAO', '{{OU_PADRAO}}', 'Unidade Organizacional padrão no AD', 'OU=Estacoes,DC=comara,DC=intraer', 'dominio', FALSE, 23),
    ('GRUPO_ADMIN', '{{GRUPO_ADMIN}}', 'Grupo administrador do domínio', 'Domain Admins', 'dominio', TRUE, 24),
    ('OFFLINE_AUTH_ENABLED', '{{OFFLINE_AUTH_ENABLED}}', 'Habilitar autenticação offline', 'true', 'dominio', FALSE, 25),
    ('OFFLINE_AUTH_DAYS', '{{OFFLINE_AUTH_DAYS}}', 'Dias para cache de credenciais offline', '30', 'dominio', FALSE, 26),
    -- Arquivos
    ('SERVIDOR_ARQUIVOS', '{{SERVIDOR_ARQUIVOS}}', 'Servidor de arquivos (SMB/NFS)', '10.108.64.20', 'arquivos', FALSE, 30),
    ('COMPARTILHAMENTOS', '{{COMPARTILHAMENTOS}}', 'Lista de compartilhamentos (separados por vírgula)', 'publico,usuarios,setores', 'arquivos', FALSE, 31),
    ('MOUNT_BASE', '{{MOUNT_BASE}}', 'Base de montagem para compartilhamentos', '/mnt/servidor', 'arquivos', FALSE, 32),
    -- Navegadores (extended)
    ('PROXY_MODE', '{{PROXY_MODE}}', 'Modo de proxy: NONE, MANUAL, PAC', 'MANUAL', 'navegador', FALSE, 40),
    ('PAC_URL', '{{PAC_URL}}', 'URL do arquivo PAC (Proxy Auto-Config)', '', 'navegador', FALSE, 41),
    ('NO_PROXY', '{{NO_PROXY}}', 'Lista de exceções de proxy (separadas por vírgula)', 'localhost,127.0.0.1,comara.intraer', 'navegador', FALSE, 42),
    -- Branding (extended)
    ('DISPLAY_NAME', '{{DISPLAY_NAME}}', 'Nome de exibição da OM', 'Comando da Comara', 'branding', FALSE, 50),
    ('WALLPAPER_LOGIN_URL', '{{WALLPAPER_LOGIN_URL}}', 'URL do wallpaper da tela de login', '', 'branding', FALSE, 51),
    ('GREETER_URL', '{{GREETER_URL}}', 'URL do greeter personalizado', '', 'branding', FALSE, 52),
    ('THEME', '{{THEME}}', 'Tema GTK a ser aplicado', 'Adwaita', 'branding', FALSE, 53),
    ('CONKY_PROFILE', '{{CONKY_PROFILE}}', 'Perfil do Conky para monitoração', 'default', 'branding', FALSE, 54),
    -- Inventário (extended)
    ('GLPI_SERVER', '{{GLPI_SERVER}}', 'Servidor GLPI para inventário', '', 'inventario', FALSE, 60),
    ('INVENTORY_ENABLED', '{{INVENTORY_ENABLED}}', 'Habilitar inventário automático', 'true', 'inventario', FALSE, 61),
    -- Acesso Remoto
    ('REMOTE_METHOD', '{{REMOTE_METHOD}}', 'Método de acesso remoto (ssh, xrdp, anydesk)', 'ssh', 'acesso_remoto', FALSE, 70),
    ('REMOTE_SERVER', '{{REMOTE_SERVER}}', 'Servidor de acesso remoto', '', 'acesso_remoto', FALSE, 71),
    -- Impressoras (extended)
    ('DEFAULT_PRINTER', '{{DEFAULT_PRINTER}}', 'Impressora padrão', '', 'impressoras', FALSE, 80),
    ('PRINTERS', '{{PRINTERS}}', 'Lista de impressoras (separadas por vírgula)', '', 'impressoras', FALSE, 81),
    -- Certificados
    ('CERTIFICATE_BUNDLE', '{{CERTIFICATE_BUNDLE}}', 'URL do bundle de certificados CA', '', 'certificados', FALSE, 90),
    ('CERTIFICATE_AUTO_INSTALL', '{{CERTIFICATE_AUTO_INSTALL}}', 'Instalar certificados automaticamente', 'true', 'certificados', FALSE, 91),
    -- Repositórios
    ('REPOSITORY_MODE', '{{REPOSITORY_MODE}}', 'Modo de repositório: PUBLIC, MIRROR, HYBRID, CUSTOM', 'MIRROR', 'repositorios', TRUE, 100),
    ('REPOSITORY_URL', '{{REPOSITORY_URL}}', 'URL do repositório espelho', 'https://softwarelivre.comara.intraer', 'repositorios', FALSE, 101),
    ('REPOSITORY_FALLBACK', '{{REPOSITORY_FALLBACK}}', 'URL de repositório fallback (internet)', 'http://deb.debian.org/debian', 'repositorios', FALSE, 102)
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 4. Insert default variable values for organization ID=1
--    Only for variables that don't already have a value set
-- ---------------------------------------------------------------------------
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT 1, vd.id, vd.default_value
FROM variable_definitions vd
WHERE NOT EXISTS (
    SELECT 1 FROM organization_variables ov
    WHERE ov.organization_id = 1 AND ov.variable_id = vd.id
)
AND vd.default_value IS NOT NULL AND vd.default_value != '';

-- ---------------------------------------------------------------------------
-- 5. Set OM_ACRONYM value for org 1
-- ---------------------------------------------------------------------------
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT 1, vd.id, 'COMARA'
FROM variable_definitions vd
WHERE vd.name = 'OM_ACRONYM'
AND NOT EXISTS (
    SELECT 1 FROM organization_variables ov
    WHERE ov.organization_id = 1 AND ov.variable_id = vd.id
);

-- End of schema update v2
