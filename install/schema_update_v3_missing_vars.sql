-- Add missing variable definitions referenced in code but absent from catalog
-- OM_NAME: used by generateDefaultVariables() and GAP-BE migration
-- DC_SECUNDARIO_IP: used by GAP-BE migration

INSERT INTO variable_definitions (name, placeholder, description, default_value, category, is_required, display_order)
VALUES
    ('OM_NAME', '{{OM_NAME}}', 'Nome completo da Organizacao Militar', '', 'identidade', FALSE, 100),
    ('DC_SECUNDARIO_IP', '{{DC_SECUNDARIO_IP}}', 'IP do Controlador de Dominio secundario', '', 'dominio', FALSE, 101)
ON CONFLICT (name) DO NOTHING;
