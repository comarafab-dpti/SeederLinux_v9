-- ============================================================================
-- SeederLinux Lite - Schema Update v5: UX Refactor
-- ============================================================================
-- Reorganiza categorias, atualiza tipos e adiciona CONKY_CONFIG.
-- Safe to re-run: usa UPDATE simples e INSERT ON CONFLICT DO NOTHING.
-- ============================================================================

-- 1) Move DNS para a aba Rede
UPDATE variable_definitions SET category = 'rede' WHERE name IN ('DNS_PRIMARIO','DNS_SECUNDARIO','DNS_INTERNET');

-- 2) Cria categoria "assets" para imagens (wallpaper, logo, greeter)
UPDATE variable_definitions SET category = 'assets', type = 'image'
    WHERE name IN ('WALLPAPER_URL','WALLPAPER_LOGIN_URL','LOGO_URL','GREETER_URL');

-- 3) Cria categoria "monitoramento" para Conky
UPDATE variable_definitions SET category = 'monitoramento', type = 'select'
    WHERE name = 'CONKY_PROFILE';

-- 4) Muda tipo de listas para "tags" (chips input)
UPDATE variable_definitions SET type = 'tags'
    WHERE name IN ('COMPARTILHAMENTOS','PRINTERS','NO_PROXY');

-- 5) Corrige categoria de OM_NAME (era 'identidade' orfa)
UPDATE variable_definitions SET category = 'branding' WHERE name = 'OM_NAME';

-- 6) Insere CONKY_CONFIG (JSON expandido)
INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order) VALUES
('CONKY_CONFIG', '{{CONKY_CONFIG}}',
 'Configuracao avancada do Conky (JSON: cores, posicao, modulos exibidos)',
 'json_conky', 'monitoramento', FALSE,
 '{"position":"top_right","transparent":true,"color_text":"#FFFFFF","color_bg":"#000000","font_size":10,"gap_x":10,"gap_y":40,"show_cpu":true,"show_ram":true,"show_disk":true,"disk_partition":"/","show_network":true,"network_interface":"eth0","show_top_processes":true,"show_datetime":true,"update_interval":1.0}',
 89)
ON CONFLICT (name) DO NOTHING;

-- 7) Seed CONKY_CONFIG para org 1
INSERT INTO organization_variables (organization_id, variable_id, value)
SELECT 1, id, default_value FROM variable_definitions WHERE name = 'CONKY_CONFIG'
ON CONFLICT (organization_id, variable_id) DO NOTHING;
