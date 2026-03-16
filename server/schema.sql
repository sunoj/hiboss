-- hiboss D1 database schema

-- API keys for agent authentication
CREATE TABLE IF NOT EXISTS api_keys (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL,           -- human-readable name for this agent
  key_hash TEXT NOT NULL UNIQUE,-- SHA-256 hash of the API key
  callback_url TEXT,            -- webhook URL for push notifications
  default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('critical', 'high', 'normal', 'low')),
  rate_limit INTEGER,           -- max messages per minute, NULL = unlimited
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT
);

-- Messages between agents and bosses
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL,       -- which agent sent/receives this
  direction TEXT NOT NULL CHECK (direction IN ('agent_to_boss', 'boss_to_agent')),
  mode TEXT NOT NULL CHECK (mode IN ('async', 'blocking')),
  channel TEXT CHECK (channel IN ('discord', 'telegram', 'email')),
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read', 'replied')),
  reply_to TEXT REFERENCES messages(id),  -- if this is a reply, points to original
  priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('critical', 'high', 'normal', 'low')),
  idempotency_key TEXT,        -- client-provided key for dedup
  metadata TEXT,                -- JSON blob for extra data
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (agent_id) REFERENCES api_keys(id)
);

-- Channel configurations (per agent)
CREATE TABLE IF NOT EXISTS channel_configs (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('discord', 'telegram', 'email')),
  config TEXT NOT NULL,         -- JSON: { webhook_url, chat_id, email, etc. }
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (agent_id) REFERENCES api_keys(id),
  UNIQUE(agent_id, channel)
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_messages_agent ON messages(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(agent_id, direction, status);
CREATE INDEX IF NOT EXISTS idx_messages_reply ON messages(reply_to);

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
