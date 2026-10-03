-- Devices group the per-runtime agent profiles enrolled from one machine.
-- A join request now carries a device and a list of profiles; one approval
-- creates every profile's agent under one device. Pending requests are transient
-- and do not survive the table replacement.
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  host TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
ALTER TABLE api_keys ADD COLUMN device_id TEXT REFERENCES devices(id);
CREATE INDEX idx_api_keys_device ON api_keys(device_id) WHERE device_id IS NOT NULL;
DROP TABLE IF EXISTS join_requests;
CREATE TABLE join_requests (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  poll_token_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  device_label TEXT NOT NULL,
  device_host TEXT,
  device_id TEXT REFERENCES devices(id),
  profiles TEXT NOT NULL,
  delivery TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_join_requests_status ON join_requests(status, created_at DESC);
