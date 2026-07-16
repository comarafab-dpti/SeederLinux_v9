/*
# Reorder core_proxy.sh to last position and rename ADMIN_PASSWORD to ADMIN_PASSWORD_B64

## Changes

### 1. Execution order reordering
- core_proxy.sh moves from execution_order 5 to 17 (last position, after all package installs)
- Scripts previously at positions 6-16 shift down by 1 (6->5, 7->6, ..., 16->15)
- This ensures proxy is configured AFTER all apt-get install operations complete,
  preventing 407 proxy authentication errors during package installation

### 2. Variable rename: ADMIN_PASSWORD -> ADMIN_PASSWORD_B64
- Renames variable_definitions entry from ADMIN_PASSWORD to ADMIN_PASSWORD_B64
- Updates description to clarify base64 encoding (obfuscation, not encryption)
- Updates placeholder accordingly
- Existing organization_variables rows are preserved (linked by variable_id)

### Security notes
- ADMIN_PASSWORD_B64 stores the password base64-encoded for simple obfuscation
- This is NOT encryption - base64 is trivially decodable
- Admins should prefer leaving the field blank (interactive prompt at runtime)
*/

-- ============================================================
-- 1. Reorder execution_order for core scripts
-- ============================================================

-- First, move core_proxy.sh to 17 (temporarily out of the way)
UPDATE scripts SET execution_order = 99 WHERE filename = 'core_proxy.sh' AND is_core = true;

-- Shift scripts 6-16 down by 1 (6->5, 7->6, ..., 16->15)
UPDATE scripts SET execution_order = execution_order - 1
WHERE is_core = true AND execution_order BETWEEN 6 AND 16;

-- Now set core_proxy.sh to 17
UPDATE scripts SET execution_order = 17 WHERE filename = 'core_proxy.sh' AND is_core = true;

-- ============================================================
-- 2. Rename ADMIN_PASSWORD -> ADMIN_PASSWORD_B64
-- ============================================================

-- Update the variable definition (if it exists)
UPDATE variable_definitions
SET name = 'ADMIN_PASSWORD_B64',
    placeholder = '{{ADMIN_PASSWORD_B64}}',
    description = 'Senha do admin do AD codificada em base64 (ofuscacao simples, NAO e criptografia). Deixe em branco para perguntar na execucao.'
WHERE name = 'ADMIN_PASSWORD';

-- If ADMIN_PASSWORD doesn't exist yet, insert it
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
SELECT 'ADMIN_PASSWORD_B64', '{{ADMIN_PASSWORD_B64}}',
       'Senha do admin do AD codificada em base64 (ofuscacao simples, NAO e criptografia). Deixe em branco para perguntar na execucao.',
       'password', 'dominio', FALSE, '', 95
WHERE NOT EXISTS (SELECT 1 FROM variable_definitions WHERE name = 'ADMIN_PASSWORD_B64');

-- Ensure all active organizations have this variable
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT o.id, vd.id, ''
FROM organizations o
CROSS JOIN variable_definitions vd
WHERE vd.name = 'ADMIN_PASSWORD_B64'
  AND o.is_active = true
  AND NOT EXISTS (
    SELECT 1 FROM organization_variables ov
    WHERE ov.organization_id = o.id AND ov.variable_id = vd.id
  );

-- Add 'both' option to AUTH_METHOD description
UPDATE variable_definitions
SET description = 'Metodo de autenticacao: sssd, winbind ou both (tentar SSSD primeiro, fallback para Winbind)'
WHERE name = 'AUTH_METHOD';
