-- Integration agents receive Discord-compatible webhook posts and never hold keys.
-- An integration owns one project and one session, so its messages group in the apps.
-- Each webhook URL is a send-only credential: a numeric id and a hashed token.

ALTER TABLE api_keys ADD COLUMN kind TEXT NOT NULL DEFAULT 'agent'
  CHECK (kind IN ('agent', 'integration'));

CREATE TABLE agent_webhooks (
  id TEXT PRIMARY KEY CHECK (length(id) BETWEEN 17 AND 20 AND id NOT GLOB '*[^0-9]*'),
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  session_id TEXT NOT NULL REFERENCES sessions(id),
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  priority_cap TEXT NOT NULL DEFAULT 'normal' CHECK (priority_cap IN ('low', 'normal', 'high')),
  created_by_agent_id TEXT NOT NULL REFERENCES api_keys(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  revoked_at TEXT
);

CREATE INDEX idx_agent_webhooks_agent ON agent_webhooks(agent_id, created_at DESC);
