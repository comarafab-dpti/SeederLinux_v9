-- ============================================================================
-- SeederLinux - Correção: Reordenar scripts, adicionar variáveis
-- ============================================================================

-- ============================================================================
-- 1. Atualizar execution_order dos scripts Core
-- ============================================================================

-- core_proxy.sh: 05 -> 17 (último)
UPDATE scripts SET execution_order = 17 WHERE filename = 'core_proxy.sh' AND is_core = true;

-- Scripts 06-16 movidos para 05-15
UPDATE scripts SET execution_order = 5  WHERE filename = 'core_browser.sh'           AND is_core = true;
UPDATE scripts SET execution_order = 6  WHERE filename = 'core_inventory.sh'         AND is_core = true;
UPDATE scripts SET execution_order = 7  WHERE filename = 'core_printers.sh'          AND is_core = true;
UPDATE scripts SET execution_order = 8  WHERE filename = 'core_vnc.sh'               AND is_core = true;
UPDATE scripts SET execution_order = 9  WHERE filename = 'core_conky.sh'            AND is_core = true;
UPDATE scripts SET execution_order = 10 WHERE filename = 'core_apps.sh'             AND is_core = true;
UPDATE scripts SET execution_order = 11 WHERE filename = 'core_legados.sh'          AND is_core = true;
UPDATE scripts SET execution_order = 12 WHERE filename = 'core_config.sh'          AND is_core = true;
UPDATE scripts SET execution_order = 13 WHERE filename = 'core_branding.sh'        AND is_core = true;
UPDATE scripts SET execution_order = 14 WHERE filename = 'core_logon.sh'           AND is_core = true;
UPDATE scripts SET execution_order = 15 WHERE filename = 'core_logoff.sh'          AND is_core = true;
UPDATE scripts SET execution_order = 16 WHERE filename = 'core_session_lightdm.sh' AND is_core = true;
UPDATE scripts SET execution_order = 16 WHERE filename = 'core_session_gdm3.sh'    AND is_core = true;
UPDATE scripts SET execution_order = 16 WHERE filename = 'core_session_sddm.sh'    AND is_core = true;

-- ============================================================================
-- 2. Adicionar novas variáveis ao catálogo
-- ============================================================================

-- ADMIN_PASSWORD_B64 (senha do AD em base64)
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('ADMIN_PASSWORD_B64', '{{ADMIN_PASSWORD_B64}}', 'Senha do administrador do dominio (codificada em base64)', 'password', 'dominio', FALSE, '', 14)
ON CONFLICT (name) DO NOTHING;

-- INSTALL_JAVA8 (substitui parte de INSTALL_LEGADOS)
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('INSTALL_JAVA8', '{{INSTALL_JAVA8}}', 'Instalar Java 8 para sistemas legados?', 'boolean', 'aplicacoes', FALSE, 'false', 111)
ON CONFLICT (name) DO NOTHING;

-- INSTALL_FIREFOX52 (substitui parte de INSTALL_LEGADOS)
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES ('INSTALL_FIREFOX52', '{{INSTALL_FIREFOX52}}', 'Instalar Firefox 52.7 ESR para sistemas legados?', 'boolean', 'aplicacoes', FALSE, 'false', 112)
ON CONFLICT (name) DO NOTHING;

-- ============================================================================
-- 3. Atualizar AUTH_METHOD para incluir opção 'both'
-- ============================================================================
UPDATE variable_definitions SET description = 'Metodo de autenticacao: sssd, winbind ou both (SSSD com fallback Winbind)'
WHERE name = 'AUTH_METHOD';

-- ============================================================================
-- 4. Seed: criar organization_variables para as novas variáveis em todas as OMs
-- ============================================================================
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT o.id, vd.id, COALESCE(vd.default_value, '')
FROM organizations o
CROSS JOIN variable_definitions vd
WHERE vd.name IN ('ADMIN_PASSWORD_B64', 'INSTALL_JAVA8', 'INSTALL_FIREFOX52')
  AND o.is_active = true
ON CONFLICT (organization_id, variable_id) DO NOTHING;

-- ============================================================================
-- 5. Migrar valores existentes de INSTALL_LEGADOS=true para as novas variáveis
-- ============================================================================
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT ov.organization_id, vd_java8.id, 'true'
FROM organization_variables ov
JOIN variable_definitions vd ON vd.id = ov.variable_id AND vd.name = 'INSTALL_LEGADOS'
JOIN variable_definitions vd_java8 ON vd_java8.name = 'INSTALL_JAVA8'
WHERE ov.value = 'true'
ON CONFLICT (organization_id, variable_id) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT ov.organization_id, vd_ff52.id, 'true'
FROM organization_variables ov
JOIN variable_definitions vd ON vd.id = ov.variable_id AND vd.name = 'INSTALL_LEGADOS'
JOIN variable_definitions vd_ff52 ON vd_ff52.name = 'INSTALL_FIREFOX52'
WHERE ov.value = 'true'
ON CONFLICT (organization_id, variable_id) DO UPDATE SET value = EXCLUDED.value;