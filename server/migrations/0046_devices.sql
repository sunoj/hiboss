-- Devices group the per-runtime agent profiles enrolled from one machine.
-- A join request now carries a device and a list of profiles; one approval
-- creates every profile's agent under one device. Once any agent exists, a join
-- needs a single-use invite minted by an enrolled agent. Pending requests are
-- transient and do not survive the table replacement.
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  host TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
ALTER TABLE api_keys ADD COLUMN device_id TEXT REFERENCES devices(id);
CREATE INDEX idx_api_keys_device ON api_keys(device_id) WHERE device_id IS NOT NULL;
CREATE TABLE device_invites (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  token_hash TEXT NOT NULL UNIQUE,
  inviter_agent_id TEXT NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
  inviter_label TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_device_invites_inviter ON device_invites(inviter_agent_id, expires_at);
DROP TABLE IF EXISTS join_requests;
CREATE TABLE join_requests (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  poll_token_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  device_label TEXT NOT NULL,
  device_host TEXT,
  device_id TEXT REFERENCES devices(id),
  profiles TEXT NOT NULL,
  invite_id TEXT,
  inviter_label TEXT,
  verification_code TEXT,
  delivery TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_join_requests_status ON join_requests(status, created_at DESC);
