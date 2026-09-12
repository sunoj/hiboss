-- api_keys remains the agent identity table. Only credentials move to agent_keys.
-- Relax the legacy NOT NULL constraint so new identities need no legacy hash.
-- Rebuild only this small table, preserving its name, IDs and all incoming FKs.
-- No existing incoming FK cascades on delete. Create agent_keys AFTER the rebuild.
PRAGMA defer_foreign_keys = ON;
CREATE TABLE api_keys_next (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL,
  key_hash TEXT UNIQUE,
  callback_url TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('critical', 'high', 'normal', 'low')),
  rate_limit INTEGER,
  channel_routing TEXT,
  avatar_url TEXT,
  role TEXT,
  session_info TEXT,
  is_admin INTEGER NOT NULL DEFAULT 0
);
INSERT INTO api_keys_next
  (id, name, key_hash, callback_url, created_at, last_used_at, default_priority,
   rate_limit, channel_routing, avatar_url, role, session_info, is_admin)
SELECT id, name, key_hash, callback_url, created_at, last_used_at, default_priority,
  rate_limit, channel_routing, avatar_url, CASE WHEN role = 'admin' THEN NULL ELSE role END,
  session_info, CASE WHEN role = 'admin' THEN 1 ELSE 0 END FROM api_keys;
DROP TABLE api_keys;
ALTER TABLE api_keys_next RENAME TO api_keys;
CREATE UNIQUE INDEX idx_api_keys_name ON api_keys(name);
PRAGMA defer_foreign_keys = OFF;

CREATE TABLE agent_keys (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
  key_hash TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  revoked_at TEXT
);
CREATE INDEX idx_agent_keys_agent ON agent_keys(agent_id, created_at DESC);
INSERT INTO agent_keys (agent_id, key_hash, label, created_at, last_used_at)
SELECT id, key_hash, 'migrated', created_at, last_used_at FROM api_keys;
-- Keep legacy hashes unchanged for the deploy-only fallback. Stop all runtime writes.
-- Drop api_keys.key_hash and the fallback in a later phase after parity is confirmed.
