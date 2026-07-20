-- ============================================================================
-- Migration: Adicionar coluna description em deploy_bundles
-- ============================================================================
-- Executa: psql -U seeder -d seederlinux -f migration_add_bundle_description.sql
-- ============================================================================

-- Adicionar coluna description se nao existir
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'deploy_bundles' AND column_name = 'description'
    ) THEN
        ALTER TABLE deploy_bundles ADD COLUMN description TEXT;
        RAISE NOTICE 'Coluna description adicionada em deploy_bundles';
    ELSE
        RAISE NOTICE 'Coluna description ja existe em deploy_bundles';
    END IF;
END $$;
