-- v0.5: Smart Routing — routing rules and agent groups

-- Routing rules: keyword/regex patterns route incoming boss messages to agents
CREATE TABLE IF NOT EXISTS routing_rules (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  owner_id TEXT NOT NULL,          -- boss (api_key id) who owns this rule
  channel TEXT NOT NULL CHECK (channel IN ('discord', 'telegram', 'email')),
  pattern TEXT NOT NULL,           -- regex pattern to match message body
  target_agent_id TEXT NOT NULL,   -- agent to route matching messages to
  priority INTEGER NOT NULL DEFAULT 0, -- higher = evaluated first
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (owner_id) REFERENCES api_keys(id),
  FOREIGN KEY (target_agent_id) REFERENCES api_keys(id)
);

CREATE INDEX IF NOT EXISTS idx_routing_rules_channel ON routing_rules(channel, enabled, priority DESC);

-- Agent groups: named groups for broadcast messaging
CREATE TABLE IF NOT EXISTS agent_groups (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Agent group membership
CREATE TABLE IF NOT EXISTS agent_group_members (
  group_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  added_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (group_id, agent_id),
  FOREIGN KEY (group_id) REFERENCES agent_groups(id) ON DELETE CASCADE,
  FOREIGN KEY (agent_id) REFERENCES api_keys(id)
);
