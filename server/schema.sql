-- hiboss D1 database schema (consolidated from migrations 0001-0030)
-- This file reflects the final schema state. For incremental changes, see migrations/.

-- API keys for agent authentication
CREATE TABLE IF NOT EXISTS api_keys (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL UNIQUE,
  callback_url TEXT,
  default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('critical', 'high', 'normal', 'low')),
  rate_limit INTEGER,
  channel_routing TEXT,
  avatar_url TEXT,
  role TEXT,
  session_info TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT
);

-- Messages between agents, bosses, and peer agents
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('agent_to_boss', 'boss_to_agent', 'agent_to_agent')),
  mode TEXT NOT NULL CHECK (mode IN ('async', 'blocking')),
  channel TEXT CHECK (channel IN ('discord', 'telegram', 'email', 'api')),
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'read', 'replied', 'expired')),
  reply_to TEXT REFERENCES messages(id),
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

CREATE INDEX IF NOT EXISTS idx_messages_agent ON messages(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(agent_id, direction, status);
CREATE INDEX IF NOT EXISTS idx_messages_reply ON messages(reply_to);
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_idempotency ON messages(agent_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_target ON messages(target_agent_id) WHERE target_agent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_target_session ON messages(target_session_id) WHERE target_session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_expires_at ON messages(expires_at) WHERE expires_at IS NOT NULL;

-- Deferred channel deliveries blocked by boss quiet hours
CREATE TABLE IF NOT EXISTS delivery_queue (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  message_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  channel TEXT NOT NULL,
  config TEXT NOT NULL,
  scheduled_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'delivered', 'failed')),
  error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (message_id) REFERENCES messages(id)
);

CREATE INDEX IF NOT EXISTS idx_delivery_queue_pending ON delivery_queue(status, scheduled_at) WHERE status = 'pending';

-- Channel configurations (per agent)
CREATE TABLE IF NOT EXISTS channel_configs (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('discord', 'telegram', 'email')),
  config TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (agent_id) REFERENCES api_keys(id),
  UNIQUE(agent_id, channel)
);

-- Routing rules: regex patterns route incoming boss messages to agents
CREATE TABLE IF NOT EXISTS routing_rules (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  owner_id TEXT NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('discord', 'telegram', 'email')),
  pattern TEXT NOT NULL,
  target_agent_id TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (owner_id) REFERENCES api_keys(id),
  FOREIGN KEY (target_agent_id) REFERENCES api_keys(id)
);

CREATE INDEX IF NOT EXISTS idx_routing_rules_channel ON routing_rules(channel, enabled, priority DESC);

-- Agent groups for broadcast messaging
CREATE TABLE IF NOT EXISTS agent_groups (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  owner_id TEXT REFERENCES api_keys(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS agent_group_members (
  group_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  added_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (group_id, agent_id),
  FOREIGN KEY (group_id) REFERENCES agent_groups(id) ON DELETE CASCADE,
  FOREIGN KEY (agent_id) REFERENCES api_keys(id)
);

-- Boss management
CREATE TABLE IF NOT EXISTS bosses (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'manager', 'viewer')),
  telegram_user_id TEXT,
  discord_user_id TEXT,
  agent_id TEXT REFERENCES api_keys(id),
  preferences TEXT DEFAULT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_telegram ON bosses(telegram_user_id) WHERE telegram_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_discord ON bosses(discord_user_id) WHERE discord_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_agent ON bosses(agent_id) WHERE agent_id IS NOT NULL;

-- Independent bearer tokens and short-lived QR pairing codes for bosses
CREATE TABLE IF NOT EXISTS boss_tokens (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  revoked_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_boss_tokens_boss ON boss_tokens(boss_id, created_at DESC);

-- Optional device-held signing keys. A token with a live key must sign messages.
CREATE TABLE IF NOT EXISTS boss_signing_keys (
  id TEXT PRIMARY KEY,
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  boss_token_id TEXT NOT NULL UNIQUE REFERENCES boss_tokens(id) ON DELETE CASCADE,
  algorithm TEXT NOT NULL CHECK (algorithm = 'ES256'),
  client_kind TEXT NOT NULL CHECK (client_kind IN ('ios', 'macos')),
  public_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  revoked_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_boss_signing_keys_boss
  ON boss_signing_keys(boss_id, created_at DESC);

CREATE TABLE IF NOT EXISTS boss_pairing_codes (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  redeemed_token_id TEXT REFERENCES boss_tokens(id) ON DELETE SET NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_boss_pairing_codes_expiry ON boss_pairing_codes(expires_at);

-- Boss-agent access control
CREATE TABLE IF NOT EXISTS boss_agent_access (
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  PRIMARY KEY (boss_id, agent_id)
);

-- Boss iOS devices for APNs delivery
CREATE TABLE IF NOT EXISTS boss_devices (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  device_token TEXT NOT NULL UNIQUE,
  bundle_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  platform TEXT NOT NULL DEFAULT 'ios' CHECK (platform = 'ios'),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_boss_devices_boss ON boss_devices(boss_id, last_seen_at DESC);

-- Audit log
CREATE TABLE IF NOT EXISTS audit_log (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  actor_type TEXT NOT NULL CHECK (actor_type IN ('boss', 'agent', 'system')),
  actor_id TEXT NOT NULL,
  action TEXT NOT NULL,
  resource_type TEXT,
  resource_id TEXT,
  details TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON audit_log(actor_type, actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log(action, created_at DESC);

-- Sessions: ephemeral workspace registrations
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL,
  label TEXT,
  branch TEXT,
  cwd TEXT,
  status TEXT NOT NULL DEFAULT 'working' CHECK (status IN ('working', 'blocked', 'waiting', 'idle', 'completed')),
  status_text TEXT,
  discord_thread_id TEXT,
  telegram_topic_id INTEGER,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (agent_id) REFERENCES api_keys(id)
);

CREATE INDEX IF NOT EXISTS idx_sessions_agent ON sessions(agent_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_sessions_discord_thread ON sessions(discord_thread_id) WHERE discord_thread_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sessions_telegram_topic ON sessions(telegram_topic_id) WHERE telegram_topic_id IS NOT NULL;

-- Join requests: device onboarding
CREATE TABLE IF NOT EXISTS join_requests (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL,
  poll_token TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  api_key_id TEXT REFERENCES api_keys(id),
  api_key TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_join_requests_token ON join_requests(poll_token);
CREATE INDEX IF NOT EXISTS idx_join_requests_status ON join_requests(status, created_at DESC);

-- Progress feed posts: deliberately separate from messages and delivery.
CREATE TABLE IF NOT EXISTS progress_posts (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  session_id TEXT,
  project TEXT NOT NULL,
  body TEXT NOT NULL,
  media TEXT,
  tags TEXT,
  agent_label TEXT,
  model TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_progress_created ON progress_posts(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_progress_project ON progress_posts(project, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_progress_agent ON progress_posts(agent_id, created_at DESC, id DESC);

-- Progress feed teams and boss likes.
CREATE TABLE IF NOT EXISTS progress_teams (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  project TEXT NOT NULL UNIQUE,
  handle TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  bio TEXT,
  avatar_url TEXT,
  created_by_agent_id TEXT REFERENCES api_keys(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS progress_likes (
  post_id TEXT NOT NULL REFERENCES progress_posts(id) ON DELETE CASCADE,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (post_id, boss_id)
);

CREATE INDEX IF NOT EXISTS idx_progress_likes_post ON progress_likes(post_id);

-- Append-only per-session event log for history and resumable SSE streams.
CREATE TABLE IF NOT EXISTS session_events (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  session_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  kind TEXT NOT NULL,
  direction TEXT,
  actor_agent_id TEXT,
  target_agent_id TEXT,
  message_id TEXT REFERENCES messages(id),
  source TEXT,
  payload TEXT,
  raw TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (session_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_session_events_cursor ON session_events(session_id, sequence);
