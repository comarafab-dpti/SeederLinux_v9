-- Add type column to variable_definitions for better UI handling
ALTER TABLE variable_definitions ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'string';

-- Update existing variable definitions with appropriate types based on name patterns
UPDATE variable_definitions SET type = 'ip' WHERE name LIKE '%IP%' OR name LIKE '%DNS%';
UPDATE variable_definitions SET type = 'domain' WHERE name LIKE '%DOMINIO%' OR name LIKE '%DOMAIN%';
UPDATE variable_definitions SET type = 'url' WHERE name LIKE '%URL%' OR name LIKE '%SERVER%' OR name LIKE '%HOMEPAGE%';
UPDATE variable_definitions SET type = 'netbios' WHERE name LIKE '%NETBIOS%';
UPDATE variable_definitions SET type = 'port' WHERE name LIKE '%PORT%';
UPDATE variable_definitions SET type = 'password' WHERE name LIKE '%PASS%' OR name LIKE '%SENHA%';
UPDATE variable_definitions SET type = 'boolean' WHERE name LIKE '%ENABLE%' OR name LIKE '%USE_%';
UPDATE variable_definitions SET type = 'array' WHERE name LIKE '%LIST%' OR name LIKE '%S_%';

-- Create index for type queries
CREATE INDEX IF NOT EXISTS idx_var_defs_type ON variable_definitions(type);