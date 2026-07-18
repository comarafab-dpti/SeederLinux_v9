-- Garante constraint UNIQUE em scripts.filename para suportar
-- ON CONFLICT (filename) DO UPDATE no insert_core_scripts.sql.
-- Idempotente: so cria se ainda nao existir.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scripts_filename_key') THEN
        ALTER TABLE scripts ADD CONSTRAINT scripts_filename_key UNIQUE (filename);
    END IF;
END $$;
