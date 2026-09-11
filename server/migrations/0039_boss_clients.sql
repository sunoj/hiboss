-- Introduce boss client instances without changing existing bearer credentials.
-- Backfill token/key ownership and retain boss_devices until the native follow-up.
CREATE TABLE boss_clients (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('ios', 'macos', 'web', 'cli')),
  label TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT,
  revoked_at TEXT
);
CREATE INDEX idx_boss_clients_boss ON boss_clients(boss_id, created_at DESC);

ALTER TABLE boss_tokens ADD COLUMN client_id TEXT REFERENCES boss_clients(id);
ALTER TABLE boss_signing_keys ADD COLUMN client_id TEXT REFERENCES boss_clients(id);
ALTER TABLE boss_devices ADD COLUMN client_id TEXT REFERENCES boss_clients(id);
CREATE INDEX idx_boss_tokens_client ON boss_tokens(client_id);
CREATE INDEX idx_boss_signing_keys_client ON boss_signing_keys(client_id);
CREATE INDEX idx_boss_devices_client ON boss_devices(client_id);

INSERT INTO boss_clients (id, boss_id, kind, label, created_at, last_seen_at)
SELECT 'client_' || t.id, t.boss_id, COALESCE(k.client_kind, 'web'),
       t.label, t.created_at, t.last_used_at
FROM boss_tokens t LEFT JOIN boss_signing_keys k ON k.boss_token_id = t.id
WHERE t.revoked_at IS NULL;

UPDATE boss_tokens SET client_id = 'client_' || id WHERE revoked_at IS NULL;
UPDATE boss_signing_keys SET client_id = (
  SELECT client_id FROM boss_tokens WHERE id = boss_signing_keys.boss_token_id
);

INSERT INTO boss_clients (boss_id, kind, label)
SELECT DISTINCT d.boss_id, 'ios', 'migrated-push' FROM boss_devices d
WHERE NOT EXISTS (SELECT 1 FROM boss_clients c WHERE c.boss_id = d.boss_id AND c.kind = 'ios');

UPDATE boss_devices SET client_id = (
  SELECT c.id FROM boss_clients c
  WHERE c.boss_id = boss_devices.boss_id AND c.kind = 'ios'
  ORDER BY c.created_at DESC, c.id DESC LIMIT 1
);
