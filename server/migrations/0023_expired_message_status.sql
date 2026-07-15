-- Rebuild messages so the status constraint accepts globally expired options.
-- Defers foreign-key checks while preserving all rows, columns, and indexes.

PRAGMA defer_foreign_keys = on;

CREATE TABLE messages_with_expired (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('agent_to_boss', 'boss_to_agent', 'agent_to_agent')),
  mode TEXT NOT NULL CHECK (mode IN ('async', 'blocking')),
  channel TEXT CHECK (channel IN ('discord', 'telegram', 'email', 'api')),
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read', 'replied', 'expired')),
  reply_to TEXT REFERENCES messages_with_expired(id),
  priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('critical', 'high', 'normal', 'low')),
  type TEXT DEFAULT 'text',
  target_agent_id TEXT,
  target_session_id TEXT,
  session_id TEXT,
  idempotency_key TEXT,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT,
  FOREIGN KEY (agent_id) REFERENCES api_keys(id)
);

INSERT INTO messages_with_expired (
  id, agent_id, direction, mode, channel, body, status, reply_to, priority,
  type, target_agent_id, target_session_id, session_id, idempotency_key,
  metadata, created_at, updated_at, expires_at
)
SELECT
  id, agent_id, direction, mode, channel, body, status, reply_to, priority,
  type, target_agent_id, target_session_id, session_id, idempotency_key,
  metadata, created_at, updated_at, expires_at
FROM messages;

DROP TABLE messages;
ALTER TABLE messages_with_expired RENAME TO messages;

CREATE INDEX idx_messages_agent ON messages(agent_id, created_at DESC);
CREATE INDEX idx_messages_status ON messages(agent_id, direction, status);
CREATE INDEX idx_messages_reply ON messages(reply_to);
CREATE UNIQUE INDEX idx_messages_idempotency
  ON messages(agent_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX idx_messages_session
  ON messages(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_messages_target
  ON messages(target_agent_id) WHERE target_agent_id IS NOT NULL;
CREATE INDEX idx_messages_target_session
  ON messages(target_session_id) WHERE target_session_id IS NOT NULL;
CREATE INDEX idx_messages_expires_at
  ON messages(expires_at) WHERE expires_at IS NOT NULL;

PRAGMA defer_foreign_keys = off;
PRAGMA foreign_key_check;
