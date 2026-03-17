-- Add token-based authentication for bosses.
-- Allows bosses to access the API directly (dashboard, mobile, etc.)
-- token_hash stores SHA-256 of the bearer token (same scheme as api_keys).

ALTER TABLE bosses ADD COLUMN token_hash TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_token ON bosses(token_hash) WHERE token_hash IS NOT NULL;
