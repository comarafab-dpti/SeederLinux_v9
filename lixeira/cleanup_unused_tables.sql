-- Drop unused tables that have no dependencies and are never referenced in code.
-- Tables: activity_log, script_executions
-- Safe to run on existing installations.

DROP TABLE IF EXISTS script_executions CASCADE;
DROP TABLE IF EXISTS activity_log CASCADE;
