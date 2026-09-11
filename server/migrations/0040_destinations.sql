-- Add boss-owned destinations and per-message delivery state without touching messages.
-- Backfill legacy credentials, accessible chats, session routes, and native clients.
CREATE TABLE channel_providers (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  provider TEXT NOT NULL CHECK (provider IN ('telegram', 'discord')),
  label TEXT NOT NULL,
  credentials TEXT NOT NULL CHECK (json_valid(credentials)),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
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
  UNIQUE (message_id, destination_id)
);
CREATE INDEX idx_message_deliveries_message ON message_deliveries(message_id);
CREATE INDEX idx_message_deliveries_retry ON message_deliveries(status, next_attempt_at);

-- A webhook identifies Discord webhook providers; otherwise the bot token does.
INSERT INTO channel_providers (id, provider, label, credentials, created_at)
SELECT 'provider_' || MIN(id), channel, channel || ' migrated',
       json_object('bot_token', MAX(json_extract(config, '$.bot_token')),
                   'webhook_url', MAX(json_extract(config, '$.webhook_url')),
                   'app_id', MAX(json_extract(config, '$.app_id'))), MIN(created_at)
FROM channel_configs
WHERE channel IN ('telegram', 'discord') AND json_valid(config)
  AND COALESCE(json_extract(config, '$.webhook_url'), json_extract(config, '$.bot_token')) IS NOT NULL
GROUP BY channel, COALESCE(json_extract(config, '$.webhook_url'), json_extract(config, '$.bot_token'));

-- This short-lived view avoids repeating the access/credential join in each backfill.
CREATE VIEW destination_backfill AS
SELECT c.id AS config_id, c.agent_id, c.channel, c.config, c.enabled, c.created_at,
       b.id AS boss_id, p.id AS provider_id,
       CAST(COALESCE(json_extract(c.config, '$.chat_id'), json_extract(c.config, '$.channel_id'), '') AS TEXT) AS external_id
FROM channel_configs c JOIN channel_providers p ON p.provider = c.channel
 AND COALESCE(json_extract(p.credentials, '$.webhook_url'), json_extract(p.credentials, '$.bot_token'))
   = COALESCE(json_extract(c.config, '$.webhook_url'), json_extract(c.config, '$.bot_token'))
JOIN bosses b ON b.role = 'admin' OR EXISTS (
  SELECT 1 FROM boss_agent_access a WHERE a.boss_id = b.id AND a.agent_id = c.agent_id
);

-- Mixed enabled values collapse with OR so an enabled legacy path is retained.
INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label, enabled, created_at)
SELECT 'destination_' || boss_id || '_' || MIN(config_id), boss_id,
       CASE channel WHEN 'telegram' THEN 'telegram_chat' ELSE 'discord_channel' END, provider_id,
       CASE channel WHEN 'telegram' THEN json_object('chat_id', external_id)
            ELSE json_object('channel_id', external_id) END,
       channel || ' ' || external_id, MAX(enabled), MIN(created_at)
FROM destination_backfill GROUP BY boss_id, provider_id, channel, external_id;

INSERT INTO destination_routes (destination_id, session_id, external_channel_id, external_thread_id)
SELECT DISTINCT d.id, s.id, f.external_id,
       CAST(CASE f.channel WHEN 'telegram' THEN COALESCE(s.telegram_topic_id, json_extract(f.config, '$.message_thread_id'))
            ELSE COALESCE(s.discord_thread_id, json_extract(f.config, '$.thread_id')) END AS TEXT)
FROM destination_backfill f JOIN boss_destinations d ON d.boss_id = f.boss_id AND d.provider_id = f.provider_id
 AND COALESCE(json_extract(d.target, '$.chat_id'), json_extract(d.target, '$.channel_id')) = f.external_id
JOIN sessions s ON s.agent_id = f.agent_id
WHERE CASE f.channel WHEN 'telegram' THEN COALESCE(s.telegram_topic_id, json_extract(f.config, '$.message_thread_id'))
      ELSE COALESCE(s.discord_thread_id, json_extract(f.config, '$.thread_id')) END IS NOT NULL;

-- Retain agent-wide topics for messages without a session using the agent name as text scope.
INSERT OR IGNORE INTO destination_routes (destination_id, project, external_channel_id, external_thread_id)
SELECT d.id, a.name, f.external_id,
       CAST(COALESCE(json_extract(f.config, '$.message_thread_id'), json_extract(f.config, '$.thread_id')) AS TEXT)
FROM destination_backfill f JOIN api_keys a ON a.id = f.agent_id
JOIN boss_destinations d ON d.boss_id = f.boss_id AND d.provider_id = f.provider_id
 AND COALESCE(json_extract(d.target, '$.chat_id'), json_extract(d.target, '$.channel_id')) = f.external_id
WHERE COALESCE(json_extract(f.config, '$.message_thread_id'), json_extract(f.config, '$.thread_id')) IS NOT NULL
ORDER BY f.config_id;

DROP VIEW destination_backfill;

INSERT INTO boss_destinations (id, boss_id, kind, client_id, target, label, enabled)
SELECT 'native_' || id, boss_id, 'native_live', id, '{}', label,
       CASE WHEN revoked_at IS NULL THEN 1 ELSE 0 END
FROM boss_clients WHERE kind IN ('ios', 'macos');

INSERT INTO boss_destinations (id, boss_id, kind, client_id, target, label)
SELECT 'apns_' || id, boss_id, 'apns', client_id, json_object('device_id', id), 'iOS push'
FROM boss_devices;
