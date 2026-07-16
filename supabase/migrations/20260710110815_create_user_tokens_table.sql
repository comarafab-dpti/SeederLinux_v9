/*
# Create user_tokens table for Bearer token authentication

1. New Tables
- `user_tokens`
  - `id` (serial, primary key)
  - `user_id` (integer, foreign key to users.id, ON DELETE CASCADE)
  - `token_hash` (varchar 255, not null) — stores password_hash() of the token
  - `expires_at` (timestamp, not null, defaults to NOW() + 24 hours)
  - `created_at` (timestamp, defaults to CURRENT_TIMESTAMP)
2. Security
- RLS NOT enabled — this table is accessed server-side only via the PHP API using the service role connection.
3. Purpose
- Stores hashed bearer tokens issued at login. The PHP API hashes the token with password_hash() and verifies it with password_verify(). Tokens expire after 24 hours.
*/

CREATE TABLE IF NOT EXISTS user_tokens (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP NOT NULL DEFAULT (NOW() + INTERVAL '24 hours'),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_tokens_user ON user_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_user_tokens_expires ON user_tokens(expires_at);
