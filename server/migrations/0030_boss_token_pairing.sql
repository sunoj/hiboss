-- Move legacy boss bearer hashes into independently revocable token records.
CREATE TABLE boss_tokens (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  revoked_at TEXT
);

CREATE INDEX idx_boss_tokens_boss ON boss_tokens(boss_id, created_at DESC);

INSERT INTO boss_tokens (boss_id, label, token_hash)
SELECT id, 'migrated', token_hash FROM bosses WHERE token_hash IS NOT NULL;

DROP INDEX IF EXISTS idx_bosses_token;
ALTER TABLE bosses DROP COLUMN token_hash;

CREATE TABLE boss_pairing_codes (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_boss_pairing_codes_expiry ON boss_pairing_codes(expires_at);
