-- Bind optional P-256 signing keys to independently revocable boss tokens.
CREATE TABLE boss_signing_keys (
  id TEXT PRIMARY KEY,
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  boss_token_id TEXT NOT NULL UNIQUE REFERENCES boss_tokens(id) ON DELETE CASCADE,
  algorithm TEXT NOT NULL CHECK (algorithm = 'ES256'),
  client_kind TEXT NOT NULL CHECK (client_kind IN ('ios', 'macos')),
  public_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  revoked_at TEXT
);

CREATE INDEX idx_boss_signing_keys_boss
  ON boss_signing_keys(boss_id, created_at DESC);
