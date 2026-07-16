-- Add per-distribution repository mirror variables
-- Allows each OM to configure mirrors for Debian, Ubuntu, Mint, and Zorin independently

INSERT INTO variable_definitions (name, placeholder, description, type, category, is_required, default_value, display_order)
VALUES
('REPOSITORY_DEBIAN_ENABLED', '{{REPOSITORY_DEBIAN_ENABLED}}', 'Habilitar mirror para Debian?', 'boolean', 'repositorios', false, 'false', 103),
('REPOSITORY_DEBIAN_URL', '{{REPOSITORY_DEBIAN_URL}}', 'URL do mirror Debian (ex: http://mirror.intraer/debian)', 'url', 'repositorios', false, '', 104),
('REPOSITORY_UBUNTU_ENABLED', '{{REPOSITORY_UBUNTU_ENABLED}}', 'Habilitar mirror para Ubuntu?', 'boolean', 'repositorios', false, 'false', 105),
('REPOSITORY_UBUNTU_URL', '{{REPOSITORY_UBUNTU_URL}}', 'URL do mirror Ubuntu (ex: http://mirror.intraer/ubuntu)', 'url', 'repositorios', false, '', 106),
('REPOSITORY_MINT_ENABLED', '{{REPOSITORY_MINT_ENABLED}}', 'Habilitar mirror para Linux Mint?', 'boolean', 'repositorios', false, 'false', 107),
('REPOSITORY_MINT_URL', '{{REPOSITORY_MINT_URL}}', 'URL do mirror Linux Mint (ex: http://mirror.intraer/mint)', 'url', 'repositorios', false, '', 108),
('REPOSITORY_ZORIN_ENABLED', '{{REPOSITORY_ZORIN_ENABLED}}', 'Habilitar mirror para Zorin OS?', 'boolean', 'repositorios', false, 'false', 109),
('REPOSITORY_ZORIN_URL', '{{REPOSITORY_ZORIN_URL}}', 'URL do mirror Zorin OS (ex: http://mirror.intraer/zorin)', 'url', 'repositorios', false, '', 110)
ON CONFLICT (name) DO NOTHING;
