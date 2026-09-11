-- hiboss D1 schema: generated from migrations through 0042; regenerate with sh scripts/check-schema.sh --regenerate | patch schema.sql
-- This file reflects the final schema state. For incremental changes, see migrations/.

-- Agent authentication

-- API keys for agent authentication
CREATE TABLE IF NOT EXISTS api_keys (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL UNIQUE,
  callback_url TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  default_priority TEXT NOT NULL DEFAULT 'normal' CHECK (default_priority IN ('critical', 'high', 'normal', 'low')),
  rate_limit INTEGER,
  channel_routing TEXT,
  avatar_url TEXT,
  role TEXT,
  session_info TEXT
);

-- Messaging and channel delivery

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
CREATE INDEX IF NOT EXISTS idx_messages_target ON messages(target_agent_id, created_at) WHERE target_agent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_target_session ON messages(target_session_id) WHERE target_session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_expires_at ON messages(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_messages_agent_expires ON messages(agent_id, expires_at) WHERE expires_at IS NOT NULL;

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

-- Agent groups

-- Agent groups for broadcast messaging
CREATE TABLE IF NOT EXISTS agent_groups (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  owner_id TEXT REFERENCES api_keys(id)
);

-- Membership of agents in broadcast groups
CREATE TABLE IF NOT EXISTS agent_group_members (
  group_id TEXT NOT NULL,
  agent_id TEXT NOT NULL,
  added_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (group_id, agent_id),
  FOREIGN KEY (group_id) REFERENCES agent_groups(id) ON DELETE CASCADE,
  FOREIGN KEY (agent_id) REFERENCES api_keys(id)
);

-- Boss identity and access

-- Boss identities and preferences
CREATE TABLE IF NOT EXISTS bosses (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'manager', 'viewer')),
  telegram_user_id TEXT,
  discord_user_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  agent_id TEXT REFERENCES api_keys(id),
  preferences TEXT DEFAULT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_telegram ON bosses(telegram_user_id) WHERE telegram_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_discord ON bosses(discord_user_id) WHERE discord_user_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_bosses_agent ON bosses(agent_id) WHERE agent_id IS NOT NULL;

-- Installed boss clients
CREATE TABLE boss_clients (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('ios', 'macos', 'web', 'cli')),
  label TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT,
  revoked_at TEXT
);
CREATE INDEX idx_boss_clients_boss ON boss_clients(boss_id, created_at DESC);

-- Independent bearer tokens and short-lived QR pairing codes for bosses
CREATE TABLE IF NOT EXISTS boss_tokens (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_used_at TEXT,
  revoked_at TEXT,
  client_id TEXT REFERENCES boss_clients(id)
);
CREATE INDEX idx_boss_tokens_client ON boss_tokens(client_id);

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
  revoked_at TEXT,
  client_id TEXT REFERENCES boss_clients(id)
);
CREATE INDEX idx_boss_signing_keys_client ON boss_signing_keys(client_id);

CREATE INDEX IF NOT EXISTS idx_boss_signing_keys_boss
  ON boss_signing_keys(boss_id, created_at DESC);

-- One-time codes for enrolling boss clients
CREATE TABLE IF NOT EXISTS boss_pairing_codes (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  redeemed_token_id TEXT REFERENCES boss_tokens(id) ON DELETE SET NULL
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
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  client_id TEXT REFERENCES boss_clients(id)
);
CREATE INDEX idx_boss_devices_client ON boss_devices(client_id);

CREATE INDEX IF NOT EXISTS idx_boss_devices_boss ON boss_devices(boss_id, last_seen_at DESC);

-- Audit history

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

-- Session registration and onboarding

-- Sessions: ephemeral workspace registrations
CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL,
  label TEXT,
  branch TEXT,
  cwd TEXT,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT NOT NULL DEFAULT (datetime('now')),
  status TEXT NOT NULL DEFAULT 'working' CHECK (status IN ('working', 'blocked', 'waiting', 'idle', 'completed')),
  status_text TEXT,
  discord_thread_id TEXT,
  telegram_topic_id INTEGER,
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

-- Progress feed

-- Progress feed posts: deliberately separate from messages and delivery.
CREATE TABLE IF NOT EXISTS progress_posts (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  session_id TEXT,
  project TEXT NOT NULL,
  body TEXT NOT NULL,
  media TEXT,
  tags TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  agent_label TEXT,
  model TEXT
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

-- Boss likes on progress feed posts
CREATE TABLE IF NOT EXISTS progress_likes (
  post_id TEXT NOT NULL REFERENCES progress_posts(id) ON DELETE CASCADE,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (post_id, boss_id)
);

CREATE INDEX IF NOT EXISTS idx_progress_likes_post ON progress_likes(post_id);

-- Session history

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

-- Live panels

-- Panel ownership, current metadata, lifecycle defaults, and durable final state
CREATE TABLE panels (
  panel_id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  target_boss_id TEXT NOT NULL REFERENCES bosses(id),
  task_key TEXT NOT NULL,
  session_id TEXT NOT NULL REFERENCES sessions(id),
  title TEXT NOT NULL,
  catalog_id TEXT NOT NULL,
  catalog_version INTEGER NOT NULL,
  definition_revision INTEGER NOT NULL DEFAULT 1,
  metadata_version INTEGER NOT NULL DEFAULT 1,
  summary_json TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  lifecycle_json TEXT NOT NULL DEFAULT '{"taskState":"running","mode":"run","expectedUpdateIntervalSeconds":15,"terminalAt":null,"dismissAt":null,"dismissalPolicy":null,"result":null}',
  final_snapshot_json TEXT,
  last_operation_id TEXT,
  supersedes_panel_id TEXT REFERENCES panels(panel_id),
  UNIQUE(agent_id, idempotency_key)
);

CREATE INDEX idx_panels_agent_created ON panels(agent_id, created_at DESC, panel_id DESC);
CREATE INDEX idx_panels_boss_created ON panels(target_boss_id, created_at DESC, panel_id DESC);

-- Immutable panel definition revisions and initial state
CREATE TABLE panel_definitions (
  panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,
  definition_revision INTEGER NOT NULL,
  protocol_version INTEGER NOT NULL,
  catalog_id TEXT NOT NULL,
  catalog_version INTEGER NOT NULL,
  spec_json TEXT NOT NULL,
  state_schema_json TEXT NOT NULL,
  initial_state_json TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (panel_id, definition_revision)
);

-- Boss-owned panel placement preferences
CREATE TABLE panel_preferences (
  panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  preference_version INTEGER NOT NULL,
  value_json TEXT NOT NULL,
  PRIMARY KEY (panel_id, boss_id)
);

-- Immutable idempotency receipts for panel operations
CREATE TABLE panel_operations (
  operation_id TEXT PRIMARY KEY,
  panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,
  agent_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  receipt_json TEXT NOT NULL,
  UNIQUE (panel_id, agent_id, idempotency_key)
);

-- Durable panel events awaiting relay delivery
CREATE TABLE panel_outbox (
  event_id TEXT PRIMARY KEY,
  panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,
  metadata_version INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  delivered_at TEXT
);

-- Panel questionnaires

-- Durable questionnaire heads and submission state
CREATE TABLE interaction_requests (
  request_id TEXT PRIMARY KEY,
  panel_id TEXT NOT NULL REFERENCES panels(panel_id),
  revision INTEGER NOT NULL CHECK (revision > 0),
  state TEXT NOT NULL CHECK (state IN ('open', 'accepted', 'withdrawn')),
  expires_at TEXT,
  blocking INTEGER NOT NULL CHECK (blocking IN (0, 1)),
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  submission_id TEXT UNIQUE,
  withdrawal_reason TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(panel_id, idempotency_key)
);
CREATE INDEX idx_interaction_panel ON interaction_requests(panel_id, created_at, request_id);

-- Immutable questionnaire definitions by revision
CREATE TABLE interaction_revisions (
  request_id TEXT NOT NULL REFERENCES interaction_requests(request_id),
  revision INTEGER NOT NULL,
  definition_json TEXT NOT NULL CHECK (json_valid(definition_json)),
  PRIMARY KEY(request_id, revision)
);

-- Accepted answers and provenance bound to an exact questionnaire revision
CREATE TABLE interaction_submissions (
  submission_id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL UNIQUE REFERENCES interaction_requests(request_id),
  revision INTEGER NOT NULL,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  payload_hash TEXT NOT NULL,
  answers_json TEXT NOT NULL CHECK (json_valid(answers_json)),
  provenance_json TEXT NOT NULL CHECK (json_valid(provenance_json)),
  accepted_at TEXT NOT NULL,
  FOREIGN KEY(request_id, revision) REFERENCES interaction_revisions(request_id, revision)
);

-- Pull-delivery acknowledgement receipts for accepted answers
CREATE TABLE interaction_deliveries (
  submission_id TEXT PRIMARY KEY REFERENCES interaction_submissions(submission_id),
  acknowledged_at TEXT
);

-- Add boss-owned destinations and per-message delivery state without touching messages.
-- Backfill legacy credentials, accessible chats, session routes, and native clients.
CREATE TABLE channel_providers (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  provider TEXT NOT NULL CHECK (provider IN ('telegram', 'discord')),
  label TEXT NOT NULL,
  credentials TEXT NOT NULL CHECK (json_valid(credentials)),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX idx_channel_providers_effective_credential ON channel_providers(
  COALESCE(NULLIF(json_extract(credentials, '$.webhook_url'), ''), json_extract(credentials, '$.bot_token'), '')
);
CREATE TABLE boss_destinations (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('telegram_chat', 'discord_channel', 'apns', 'native_live')),
  provider_id TEXT REFERENCES channel_providers(id),
  client_id TEXT REFERENCES boss_clients(id),
  target TEXT NOT NULL CHECK (json_valid(target)),
  label TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  min_priority TEXT NOT NULL DEFAULT 'low' CHECK (min_priority IN ('low', 'normal', 'high', 'critical')),
  honours_quiet_hours INTEGER NOT NULL DEFAULT 1 CHECK (honours_quiet_hours IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_boss_destinations_boss ON boss_destinations(boss_id, enabled);
CREATE TABLE destination_routes (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  destination_id TEXT NOT NULL REFERENCES boss_destinations(id) ON DELETE CASCADE,
  project TEXT,
  session_id TEXT,
  external_channel_id TEXT,
  external_thread_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (destination_id, project, session_id)
);
CREATE UNIQUE INDEX idx_destination_routes_scope ON destination_routes(destination_id, COALESCE(project, ''), COALESCE(session_id, ''));
CREATE TABLE inbound_routes (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  destination_id TEXT NOT NULL REFERENCES boss_destinations(id) ON DELETE CASCADE,
  pattern TEXT,
  target_agent_id TEXT NOT NULL REFERENCES api_keys(id),
  priority INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE message_deliveries (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  message_id TEXT NOT NULL REFERENCES messages(id),
  destination_id TEXT NOT NULL REFERENCES boss_destinations(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'delivered', 'failed')),
  external_message_id TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  external_target TEXT,
  merged_into TEXT REFERENCES message_deliveries(id) ON DELETE CASCADE,
  UNIQUE (message_id, destination_id)
);
CREATE INDEX idx_message_deliveries_message ON message_deliveries(message_id);
CREATE INDEX idx_message_deliveries_retry ON message_deliveries(status, next_attempt_at);

CREATE UNIQUE INDEX idx_message_deliveries_target ON message_deliveries(message_id, external_target);
CREATE INDEX idx_message_deliveries_merged ON message_deliveries(merged_into);
CREATE TABLE boss_external_accounts (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  provider TEXT NOT NULL CHECK (provider IN ('telegram', 'discord')),
  provider_user_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (provider, provider_user_id)
);
CREATE INDEX idx_boss_external_accounts_boss ON boss_external_accounts(boss_id);
