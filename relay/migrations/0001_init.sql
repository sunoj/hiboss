-- Push relay schema: opt-in registrations and fixed-window rate counters.
-- Handles and device secrets are stored only as SHA-256 hex digests; one row per APNs token.
CREATE TABLE IF NOT EXISTS registrations (
  handle_hash TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL UNIQUE,
  apns_token TEXT NOT NULL UNIQUE,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  created_at INTEGER NOT NULL,
  last_used_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_registrations_last_used ON registrations(last_used_at);

CREATE TABLE IF NOT EXISTS rate_counters (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rate_counters_expires ON rate_counters(expires_at);
