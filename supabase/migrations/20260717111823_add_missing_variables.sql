-- ============================================================================
-- SeederLinux - Adicionar variaveis faltantes ao catalogo
-- ============================================================================

-- AUTH_METHOD
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('AUTH_METHOD', '{{AUTH_METHOD}}', 'Metodo de autenticacao: sssd, winbind ou both (SSSD com fallback Winbind)', 'select', 'dominio', FALSE, 'sssd', 10)
ON CONFLICT (name) DO NOTHING;

-- ADMIN_USERNAME
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('ADMIN_USERNAME', '{{ADMIN_USERNAME}}', 'Usuario administrador do dominio AD', 'string', 'dominio', FALSE, 'Administrator', 13)
ON CONFLICT (name) DO NOTHING;

-- VNC_ENABLED
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('VNC_ENABLED', '{{VNC_ENABLED}}', 'Habilitar acesso remoto via VNC', 'boolean', 'acesso_remoto', FALSE, 'false', 10)
ON CONFLICT (name) DO NOTHING;

-- VNC_PASSWORD
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('VNC_PASSWORD', '{{VNC_PASSWORD}}', 'Senha do VNC (vazia = gerar automaticamente)', 'password', 'acesso_remoto', FALSE, '', 11)
ON CONFLICT (name) DO NOTHING;

-- CONKY_CONFIG
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('CONKY_CONFIG', '{{CONKY_CONFIG}}', 'Configuracao JSON do Conky (posicao, cores, fontes)', 'text', 'branding', FALSE, '', 20)
ON CONFLICT (name) DO NOTHING;

-- DESKTOP_ENV
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('DESKTOP_ENV', '{{DESKTOP_ENV}}', 'Ambiente grafico (cinnamon, mate, gnome, xfce, kde, lxde)', 'select', 'aplicacoes', FALSE, '', 100)
ON CONFLICT (name) DO NOTHING;

-- DC_IP_LIST
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('DC_IP_LIST', '{{DC_IP_LIST}}', 'Lista de IPs dos controladores de dominio (separados por espaco)', 'string', 'dominio', FALSE, '', 15)
ON CONFLICT (name) DO NOTHING;

-- Seed: criar organization_variables para as novas variaveis em todas as OMs
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT o.id, vd.id, COALESCE(vd.default_value, '')
FROM organizations o
CROSS JOIN variable_definitions vd
WHERE vd.name IN ('AUTH_METHOD', 'ADMIN_USERNAME', 'VNC_ENABLED', 'VNC_PASSWORD', 'CONKY_CONFIG', 'DESKTOP_ENV', 'DC_IP_LIST')
  AND o.is_active = true
ON CONFLICT (organization_id, variable_id) DO NOTHING;