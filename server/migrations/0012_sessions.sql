-- Sessions table: ephemeral workspace registrations for same-agent multi-session.
-- Each CC session registers here on start; heartbeat keeps last_seen fresh.

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL,
  label TEXT,
  branch TEXT,
  cwd TEXT,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (agent_id) REFERENCES api_keys(id)
);

CREATE INDEX idx_sessions_agent ON sessions(agent_id, last_seen_at DESC);

-- Add target_session_id to messages for session-level routing.
ALTER TABLE messages ADD COLUMN target_session_id TEXT;
CREATE INDEX idx_messages_target_session ON messages(target_session_id) WHERE target_session_id IS NOT NULL;
