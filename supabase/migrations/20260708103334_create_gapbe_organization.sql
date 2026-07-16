-- Create GAP-BE organization (if not exists)
INSERT INTO organizations (id, acronym, name, domain, is_active, created_at, updated_at)
SELECT nextval('organizations_id_seq'), 'GAP-BE', 'Grupamento de Apoio de Belem', 'gapbe.intraer', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
WHERE NOT EXISTS (SELECT 1 FROM organizations WHERE acronym = 'GAP-BE');

-- Get the org_id for GAP-BE (newly created or existing)
DO $$
DECLARE
    gapbe_id INTEGER;
BEGIN
    SELECT id INTO gapbe_id FROM organizations WHERE acronym = 'GAP-BE' LIMIT 1;
    
    IF gapbe_id IS NOT NULL THEN
        -- Insert default variables for GAP-BE with correct values
        INSERT INTO organization_variables (organization_id, variable_id, value)
        SELECT gapbe_id, vd.id, 
            CASE vd.name
                WHEN 'DOMINIO' THEN 'gapbe.intraer'
                WHEN 'DOMINIO_NETBIOS' THEN 'GAPBE'
                WHEN 'DC_IP' THEN '10.108.65.51'
                WHEN 'DNS_INTERNET' THEN '10.108.64.27'
                WHEN 'DC_SECUNDARIO_IP' THEN '10.108.65.52'
                WHEN 'OM_ACRONYM' THEN 'GAP-BE'
                WHEN 'OM_NAME' THEN 'Grupamento de Apoio de Belem'
                WHEN 'OCS_TAG' THEN 'GAPBE-ESTACOES'
                WHEN 'BASE_URL' THEN 'https://gapbe.intraer/seeder'
                ELSE vd.default_value
            END
        FROM variable_definitions vd
        WHERE NOT EXISTS (
            SELECT 1 FROM organization_variables ov 
            WHERE ov.organization_id = gapbe_id AND ov.variable_id = vd.id
        )
        AND vd.default_value IS NOT NULL;
    END IF;
END $$;