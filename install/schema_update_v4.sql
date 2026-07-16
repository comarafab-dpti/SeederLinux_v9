-- ============================================================================
-- SeederLinux Lite - Schema Update v4
-- Adiciona variaveis faltantes ao catalogo variable_definitions
-- ============================================================================
-- Estas variaveis sao referenciadas nos scripts Core mas nao existiam
-- no catalogo canonical (schema.sql + updates v2/v3).
-- ============================================================================

INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES
-- Dominio e Autenticacao
('AUTH_METHOD', '{{AUTH_METHOD}}', 'Metodo de autenticacao: sssd (recomendado para cache offline) ou winbind (legado)', 'select', 'dominio', FALSE, 'sssd', 110),
('DC_IP_LIST', '{{DC_IP_LIST}}', 'Lista de IPs de todos os Controladores de Dominio (separados por virgula). Ex: 10.108.64.51,10.108.64.52', 'array', 'dominio', FALSE, '', 111),
('ADMIN_USERNAME', '{{ADMIN_USERNAME}}', 'Nome de usuario administrador do dominio para realizar o ingresso', 'string', 'dominio', FALSE, 'Administrator', 112),

-- Ambiente Grafico
('DESKTOP_ENV', '{{DESKTOP_ENV}}', 'Ambiente grafico a ser instalado: cinnamon, mate, gnome, xfce, kde, lxde', 'select', 'ambiente', FALSE, 'cinnamon', 120),
('DISPLAY_MANAGER', '{{DISPLAY_MANAGER}}', 'Gerenciador de sessao: lightdm (MATE/Cinnamon/XFCE/LXDE), gdm3 (GNOME), sddm (KDE)', 'select', 'ambiente', FALSE, 'lightdm', 121),

-- Aplicacoes
('INSTALL_APPS', '{{INSTALL_APPS}}', 'Instalar OnlyOffice, Google Chrome e Firefox ESR durante o provisionamento?', 'boolean', 'aplicacoes', FALSE, 'true', 130),
('INSTALL_LEGADOS', '{{INSTALL_LEGADOS}}', 'Instalar Java 8 e Firefox 52.7 ESR para compatibilidade com sistemas legados?', 'boolean', 'aplicacoes', FALSE, 'false', 131),

-- Acesso Remoto
('VNC_ENABLED', '{{VNC_ENABLED}}', 'Habilitar servidor VNC (x11vnc) para suporte remoto?', 'boolean', 'acesso_remoto', FALSE, 'false', 140),
('VNC_PASSWORD', '{{VNC_PASSWORD}}', 'Senha do servidor VNC. Deixe em branco para gerar uma senha aleatoria', 'password', 'acesso_remoto', FALSE, '', 141)
ON CONFLICT (name) DO NOTHING;

-- Garantir que DC_IP e DNS_PRIMARIO sejam obrigatorios
UPDATE variable_definitions SET is_required = true WHERE name = 'DC_IP';
UPDATE variable_definitions SET is_required = true WHERE name = 'DNS_PRIMARIO';
