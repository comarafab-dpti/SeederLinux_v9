-- SeederLinux Lite - Admin User Setup
-- Run this to create or reset the default admin user
-- Usage: sudo -u postgres psql -d seederlinux -f setup_user.sql

-- Delete existing admin user if exists
DELETE FROM users WHERE username = 'admin';

-- Insert admin user with password: admin123
-- Hash generated with PASSWORD_BCRYPT (cost=12)
INSERT INTO users (username, password_hash, email, full_name, role, is_active)
VALUES (
    'admin',
    '$2y$12$aclfbpmKYX0DoMcu8EmQeO1xyziOBv9/WjuWR6y3/ovgF74QTaLhC',
    'admin@seeder.local',
    'Administrator',
    'admin',
    TRUE
);

-- Verify the hash works
SELECT username, full_name, role, is_active FROM users WHERE username = 'admin';
