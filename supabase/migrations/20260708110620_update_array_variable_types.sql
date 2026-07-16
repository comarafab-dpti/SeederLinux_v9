-- Update variable types to support multiple values (array type)
-- DC_IP: multiple domain controllers
-- COMPARTILHAMENTOS: multiple network shares
-- PRINTERS: multiple printer queues
-- NO_PROXY: multiple no-proxy entries

UPDATE variable_definitions SET type = 'array' WHERE name = 'DC_IP';
UPDATE variable_definitions SET type = 'array' WHERE name = 'COMPARTILHAMENTOS';
UPDATE variable_definitions SET type = 'array' WHERE name = 'PRINTERS';
UPDATE variable_definitions SET type = 'array' WHERE name = 'NO_PROXY';

-- Ensure DNS_PRIMARIO and DNS_SECUNDARIO are already array type (they are)
-- No update needed for them

-- Result: All variables that can have multiple values now use type 'array'