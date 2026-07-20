ALTER TABLE deploy_bundles ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_deploy_bundles_active ON deploy_bundles(is_active) WHERE is_active = true;

COMMENT ON COLUMN deploy_bundles.is_active IS 'Controla se o bundle aparece na pagina publica de downloads';
