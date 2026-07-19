-- Boss iOS device registry for APNs delivery.
-- Stores one row per APNs device token and owning boss.

CREATE TABLE IF NOT EXISTS boss_devices (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  device_token TEXT NOT NULL UNIQUE,
  bundle_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform = 'ios'),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_boss_devices_boss ON boss_devices(boss_id, last_seen_at DESC);
