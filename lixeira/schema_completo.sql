-- ============================================================================
-- SeederLinux Lite - Schema Completo do Banco de Dados
-- ============================================================================
-- PostgreSQL schema for SeederLinux Lite
-- Cria as tabelas: organizations, variables, scripts, bundles, users
-- e o catalogo de variaveis (placeholders {{VARIAVEL}}).
-- ============================================================================

-- ============================================================================
-- Tipos e Enums
-- ============================================================================

CREATE TYPE proxy_mode AS ENUM ('NONE', 'MANUAL', 'PAC');
CREATE TYPE repository_mode AS ENUM ('PUBLIC', 'MIRROR', 'HYBRID', 'CUSTOM');
CREATE TYPE desktop_environment AS ENUM ('cinnamon', 'mate', 'gnome', 'xfce', 'kde', 'lxde');
CREATE TYPE display_manager_type AS ENUM ('lightdm', 'gdm3', 'sddm');
CREATE TYPE remote_method_type AS ENUM ('vnc', 'ssh', 'xrdp', 'none');

-- ============================================================================
-- Tabela: organizations (OMs)
-- ============================================================================
CREATE TABLE IF NOT EXISTS organizations (
    id              SERIAL PRIMARY KEY,
    acronym         VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(255) NOT NULL,
    display_name    VARCHAR(255),
    domain          VARCHAR(255) NOT NULL,
    domain_netbios  VARCHAR(50) NOT NULL,
    dc_ip           VARCHAR(45) NOT NULL,
    dc_ip_list      TEXT,
    ou_padrao       VARCHAR(500),
    is_active       BOOLEAN DEFAULT true,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Tabela: users (administradores do painel)
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(100) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    name            VARCHAR(255),
    email           VARCHAR(255),
    is_active       BOOLEAN DEFAULT true,
    is_admin        BOOLEAN DEFAULT false,
    organization_id INTEGER REFERENCES organizations(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Tabela: variable_catalog (catalogo de variaveis/placeholders)
-- ============================================================================
-- Define todas as variaveis (placeholders {{VARIAVEL}}) disponiveis no sistema.
-- O agente Python le esta tabela para saber quais placeholders substituir.
CREATE TABLE IF NOT EXISTS variable_catalog (
    id              SERIAL PRIMARY KEY,
    variable_name   VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT NOT NULL,
    category        VARCHAR(50) NOT NULL,
    example_value   VARCHAR(500),
    is_required     BOOLEAN DEFAULT false,
    sort_order      INTEGER DEFAULT 0,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Tabela: organization_variables (valores das variaveis por OM)
-- ============================================================================
CREATE TABLE IF NOT EXISTS organization_variables (
    id              SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    variable_name   VARCHAR(100) NOT NULL,
    variable_value  TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (organization_id, variable_name)
);

-- ============================================================================
-- Tabela: scripts
-- ============================================================================
CREATE TABLE IF NOT EXISTS scripts (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    filename        VARCHAR(255) NOT NULL,
    description     TEXT,
    content         TEXT NOT NULL,
    is_core         BOOLEAN DEFAULT false,
    is_active       BOOLEAN DEFAULT true,
    execution_order INTEGER DEFAULT 0,
    version         INTEGER DEFAULT 1,
    organization_id INTEGER REFERENCES organizations(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_scripts_core ON scripts (is_core);
CREATE INDEX IF NOT EXISTS idx_scripts_order ON scripts (execution_order);
CREATE INDEX IF NOT EXISTS idx_scripts_org ON scripts (organization_id);

-- ============================================================================
-- Tabela: bundles
-- ============================================================================
CREATE TABLE IF NOT EXISTS bundles (
    id              SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    filename        VARCHAR(255),
    content         TEXT,
    desktop_env     desktop_environment,
    display_manager display_manager_type,
    status          VARCHAR(50) DEFAULT 'generated',
    created_by      INTEGER REFERENCES users(id),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_bundles_org ON bundles (organization_id);

-- ============================================================================
-- Insercao do Catalogo de Variaveis (Placeholders)
-- ============================================================================
-- Todas as variaveis {{VARIAVEL}} usadas nos scripts Core estao catalogadas aqui.

INSERT INTO variable_catalog (variable_name, description, category, example_value, is_required, sort_order) VALUES
-- Domínio e Autenticação
('DOMINIO', 'Dominio AD completo (ex: comara.intraer)', 'dominio', 'comara.intraer', true, 1),
('DOMINIO_NETBIOS', 'Nome NetBIOS do dominio', 'dominio', 'COMARA', true, 2),
('DC_IP', 'IP do Controlador de Dominio principal', 'dominio', '10.10.10.10', true, 3),
('DC_IP_LIST', 'Lista de IPs de todos os DCs (separados por espaco)', 'dominio', '10.10.10.10 10.10.10.11', false, 4),
('DNS_PRIMARIO', 'IP do DNS primario', 'dominio', '10.10.10.10', true, 5),
('DNS_SECUNDARIO', 'IP do DNS secundario', 'dominio', '10.10.10.11', false, 6),
('NTP_SERVER', 'Servidor NTP para sincronizacao de horario', 'dominio', '10.10.10.10', false, 7),
('OU_PADRAO', 'OU padrao no AD para ingresso de estacoes', 'dominio', 'OU=Estacoes,DC=comara,DC=intraer', true, 8),
('GRUPO_ADMIN', 'Grupo administrador do dominio', 'dominio', 'Domain Admins', false, 9),
('OFFLINE_AUTH_ENABLED', 'Habilitar cache de autenticacao offline (true/false)', 'dominio', 'true', false, 10),
('OFFLINE_AUTH_DAYS', 'Dias de validade do cache offline', 'dominio', '3', false, 11),

-- Rede e Proxy
('PROXY_HTTP', 'IP do servidor proxy HTTP', 'rede', '10.10.10.5', false, 12),
('PROXY_PORTA', 'Porta do servidor proxy', 'rede', '8080', false, 13),
('PROXY_URL', 'URL completa do proxy (opcional, sobrescreve IP+porta)', 'rede', 'http://10.10.10.5:8080', false, 14),
('PROXY_MODE', 'Modo de proxy: NONE, MANUAL ou PAC', 'rede', 'MANUAL', false, 15),
('PAC_URL', 'URL do arquivo PAC para configuracao automatica de proxy', 'rede', 'http://proxy.intraer/proxy.pac', false, 16),
('NO_PROXY', 'Lista de excecoes de proxy (separadas por virgula)', 'rede', 'localhost,127.0.0.1,.intraer', false, 17),
('DNS_INTERNET', 'DNS para internet (fallback durante provisionamento)', 'rede', '8.8.8.8', false, 18),

-- URLs e Servidores
('BASE_URL', 'URL base do repositorio de scripts e downloads', 'servidores', 'https://seederlinux.intraer/scripts', true, 19),
('HOMEPAGE', 'Pagina inicial do portal da OM', 'servidores', 'https://portal.intraer', false, 20),
('OCS_SERVER', 'Servidor OCS Inventory para coleta de inventario', 'servidores', 'ocs.intraer', false, 21),
('OCS_TAG', 'Tag OCS da organizacao para identificacao no inventario', 'servidores', 'COMARA', false, 22),
('PRINT_SERVER', 'Servidor de impressao (CUPS remoto)', 'servidores', 'printsrv.intraer', false, 23),
('SERVIDOR_ARQUIVOS', 'Servidor de arquivos para mapeamento de compartilhamentos', 'servidores', 'filesrv.intraer', false, 24),

-- Identidade Visual
('OM_ACRONYM', 'Sigla da OM (Organizacao Militar)', 'identidade', 'COMARA', true, 25),
('OM_NAME', 'Nome completo da OM', 'identidade', 'Comando de Apoio Logistico', true, 26),
('DISPLAY_NAME', 'Nome de exibicao da OM', 'identidade', 'COMARA-SE', false, 27),
('WALLPAPER_URL', 'URL do wallpaper do desktop', 'identidade', 'https://seederlinux.intraer/img/wallpaper.jpg', false, 28),
('WALLPAPER_LOGIN_URL', 'URL do wallpaper da tela de login', 'identidade', 'https://seederlinux.intraer/img/login.jpg', false, 29),
('LOGO_URL', 'URL do logo da OM', 'identidade', 'https://seederlinux.intraer/img/logo.png', false, 30),
('GREETER_URL', 'URL do greeter personalizado (tar.gz)', 'identidade', 'https://seederlinux.intraer/greeter.tar.gz', false, 31),
('THEME', 'Tema GTK a ser aplicado', 'identidade', 'Adwaita', false, 32),
('CONKY_PROFILE', 'Perfil do Conky para monitoracao do sistema', 'identidade', 'padrao', false, 33),

-- Ambiente Grafico
('DESKTOP_ENV', 'Ambiente grafico: cinnamon, mate, gnome, xfce, kde, lxde', 'ambiente', 'cinnamon', true, 34),
('DISPLAY_MANAGER', 'Gerenciador de display: lightdm, gdm3, sddm', 'ambiente', 'lightdm', true, 35),

-- Aplicacoes e Funcionalidades
('INSTALL_APPS', 'Instalar OnlyOffice, Chrome e Firefox ESR (true/false)', 'aplicacoes', 'true', false, 36),
('INSTALL_LEGADOS', 'Instalar Java 8 e Firefox 52.7 ESR para sistemas legados (true/false)', 'aplicacoes', 'false', false, 37),
('VNC_ENABLED', 'Habilitar x11vnc para suporte remoto (true/false)', 'aplicacoes', 'true', false, 38),
('VNC_PASSWORD', 'Senha de acesso ao VNC', 'aplicacoes', 'secretpass', false, 39),

-- Repositorios
('REPOSITORY_MODE', 'Modo de repositorio: PUBLIC, MIRROR, HYBRID, CUSTOM', 'repositorios', 'MIRROR', true, 40),
('REPOSITORY_URL', 'URL do repositorio espelho local', 'repositorios', 'http://mirror.intraer/debian', false, 41),
('REPOSITORY_FALLBACK', 'URL de fallback para repositorios (modo HYBRID)', 'repositorios', 'http://deb.debian.org/debian', false, 42),

-- Grupos e Seguranca
('GRUPO_ADMIN_AD', 'Grupo admin no AD para sudo', 'seguranca', 'Domain Admins', false, 43),
('GRUPO_ADMIN_LINUX', 'Grupo local para sudo', 'seguranca', 'admin-linux', false, 44),
('GRUPO_DASTI', 'Grupo DASTI para sudo', 'seguranca', 'dasti', false, 45),

-- Compartilhamentos e Impressoras
('COMPARTILHAMENTOS', 'Lista de compartilhamentos para mapear (separados por espaco)', 'compartilhamentos', 'publico documentos sistemas', false, 46),
('MOUNT_BASE', 'Diretorio base para montagem de compartilhamentos', 'compartilhamentos', '/mnt', false, 47),
('DEFAULT_PRINTER', 'Impressora padrao do sistema', 'compartilhamentos', 'HP-LaserJet-4001', false, 48),
('PRINTERS', 'Lista de impressoras para instalar (separadas por espaco)', 'compartilhamentos', 'HP-LaserJet-4001 HP-ColorJet-200', false, 49),

-- Outros
('REMOTE_METHOD', 'Metodo de acesso remoto: vnc, ssh, xrdp, none', 'outros', 'vnc', false, 50),
('REMOTE_SERVER', 'Servidor de acesso remoto', 'outros', 'remote.intraer', false, 51),
('CERTIFICATE_BUNDLE', 'URL do bundle de certificados CA', 'outros', 'https://seederlinux.intraer/certs/ca-bundle.crt', false, 52),
('CERTIFICATE_AUTO_INSTALL', 'Instalar certificados automaticamente (true/false)', 'outros', 'true', false, 53),
('INVENTORY_ENABLED', 'Habilitar coleta de inventario OCS (true/false)', 'outros', 'true', false, 54),
('GLPI_SERVER', 'Servidor GLPI para integracao de inventario', 'outros', 'https://glpi.intraer', false, 55),
('ADMIN_USERNAME', 'Usuario administrador do dominio para ingresso no AD', 'dominio', 'admin', false, 56)
ON CONFLICT (variable_name) DO UPDATE SET
    description = EXCLUDED.description,
    category = EXCLUDED.category,
    example_value = EXCLUDED.example_value,
    is_required = EXCLUDED.is_required,
    sort_order = EXCLUDED.sort_order;

-- ============================================================================
-- Categorias do Catalogo de Variaveis
-- ============================================================================
-- dominio          - Variaveis de dominio e autenticacao AD
-- rede             - Variaveis de rede e proxy
-- servidores       - URLs e servidores internos
-- identidade       - Identidade visual (branding)
-- ambiente         - Ambiente grafico e display manager
-- aplicacoes       - Aplicativos e funcionalidades opcionais
-- repositorios     - Configuracao de repositorios APT
-- seguranca        - Grupos e configuracoes de seguranca
-- compartilhamentos - Compartilhamentos de rede e impressoras
-- outros           - Variaveis diversas

-- ============================================================================
-- Fim do Schema
-- ============================================================================
