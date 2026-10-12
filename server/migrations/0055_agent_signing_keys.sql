-- Bind P-256 message-signing keys to agent credentials; enforcement is per agent identity.
-- A key is live while both its own row and its credential are unrevoked.
CREATE TABLE agent_signing_keys (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  key_id TEXT NOT NULL,
  agent_id TEXT NOT NULL REFERENCES api_keys(id) ON DELETE CASCADE,
  agent_key_id TEXT NOT NULL REFERENCES agent_keys(id) ON DELETE CASCADE,
  algorithm TEXT NOT NULL CHECK (algorithm = 'ES256'),
  public_key TEXT NOT NULL,
  enrolled_via TEXT NOT NULL CHECK (enrolled_via IN ('first_use', 'endorsed')),
  endorsed_by TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  revoked_at TEXT
);

CREATE UNIQUE INDEX idx_agent_signing_keys_live_credential
  ON agent_signing_keys(agent_key_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_agent_signing_keys_agent
  ON agent_signing_keys(agent_id, created_at DESC);
