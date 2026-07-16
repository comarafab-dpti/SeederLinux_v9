-- ============================================================================
-- SeederLinux Lite - Schema Update
-- Adds missing tables and columns for full MVP functionality
-- Run AFTER schema.sql
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add organization_id to users (nullable, for operador_om role)
-- ---------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS organization_id INTEGER REFERENCES organizations(id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 2. Add OM_ACRONYM variable definition (referenced in branding script)
-- ---------------------------------------------------------------------------
INSERT INTO variable_definitions (name, placeholder, description, default_value, category, is_required, display_order)
SELECT 'OM_ACRONYM', '{{OM_ACRONYM}}', 'Sigla da Organização Militar', '', 'branding', FALSE, 18
WHERE NOT EXISTS (SELECT 1 FROM variable_definitions WHERE name = 'OM_ACRONYM');

-- ---------------------------------------------------------------------------
-- 3. Table: deploy_bundles (stores generated bundles for download later)
-- ---------------------------------------------------------------------------
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

CREATE INDEX IF NOT EXISTS idx_deploy_bundles_org ON deploy_bundles(organization_id);
CREATE INDEX IF NOT EXISTS idx_deploy_bundles_date ON deploy_bundles(generated_at DESC);

-- ---------------------------------------------------------------------------
-- 4. Table: audit_events (structured audit trail with JSONB details)
-- ---------------------------------------------------------------------------
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

CREATE INDEX IF NOT EXISTS idx_audit_events_org ON audit_events(organization_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_user ON audit_events(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_entity ON audit_events(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_date ON audit_events(created_at DESC);

-- ---------------------------------------------------------------------------
-- 5. Update admin user role to admin_gap (new role naming convention)
-- ---------------------------------------------------------------------------
UPDATE users SET role = 'admin_gap' WHERE role = 'admin' AND username = 'admin';

-- ---------------------------------------------------------------------------
-- 6. Add version column to scripts (for version tracking)
-- ---------------------------------------------------------------------------
ALTER TABLE scripts ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1;

-- ---------------------------------------------------------------------------
-- 7. Add organization_id to scripts (nullable - NULL means core/shared)
-- ---------------------------------------------------------------------------
ALTER TABLE scripts ADD COLUMN IF NOT EXISTS organization_id INTEGER REFERENCES organizations(id) ON DELETE CASCADE;

-- End of schema update
