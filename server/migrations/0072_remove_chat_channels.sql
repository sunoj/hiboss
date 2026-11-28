-- Remove chat configuration while retaining messages and native delivery state.
DROP TABLE inbound_routes;
DROP TABLE destination_routes;
DROP TABLE boss_external_accounts;
DROP TABLE routing_rules;
DROP TABLE channel_configs;

DROP INDEX idx_bosses_telegram;
DROP INDEX idx_bosses_discord;
DROP INDEX idx_sessions_discord_thread;
DROP INDEX idx_sessions_telegram_topic;
ALTER TABLE bosses DROP COLUMN telegram_user_id;
ALTER TABLE bosses DROP COLUMN discord_user_id;
ALTER TABLE sessions DROP COLUMN discord_thread_id;
ALTER TABLE sessions DROP COLUMN telegram_topic_id;
ALTER TABLE api_keys DROP COLUMN channel_routing;

-- Rebuild both tables so foreign keys stay enabled and native receipts survive.
CREATE TABLE native_destinations (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('apns', 'native_live')),
  client_id TEXT REFERENCES boss_clients(id),
  target TEXT NOT NULL CHECK (json_valid(target)),
  label TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  min_priority TEXT NOT NULL DEFAULT 'low' CHECK (min_priority IN ('low', 'normal', 'high', 'critical')),
  honours_quiet_hours INTEGER NOT NULL DEFAULT 1 CHECK (honours_quiet_hours IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO native_destinations
SELECT id, boss_id, kind, client_id, target, label, enabled, min_priority, honours_quiet_hours, created_at
FROM boss_destinations WHERE kind IN ('apns', 'native_live');

CREATE TABLE native_deliveries (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  message_id TEXT NOT NULL REFERENCES messages(id),
  destination_id TEXT NOT NULL REFERENCES native_destinations(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'sent', 'delivered', 'failed')),
  external_message_id TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  external_target TEXT,
  merged_into TEXT REFERENCES native_deliveries(id) ON DELETE CASCADE,
  UNIQUE (message_id, destination_id)
);

INSERT INTO native_deliveries
SELECT old.id, old.message_id, old.destination_id, old.status, old.external_message_id,
       old.attempts, old.next_attempt_at, old.last_error, old.created_at, old.updated_at,
       old.external_target, CASE WHEN canonical_destination.id IS NOT NULL THEN old.merged_into END
FROM message_deliveries old
JOIN native_destinations destination ON destination.id = old.destination_id
LEFT JOIN message_deliveries canonical ON canonical.id = old.merged_into
LEFT JOIN native_destinations canonical_destination ON canonical_destination.id = canonical.destination_id;

DROP TABLE message_deliveries;
DROP TABLE boss_destinations;
DROP TABLE channel_providers;
ALTER TABLE native_destinations RENAME TO boss_destinations;
ALTER TABLE native_deliveries RENAME TO message_deliveries;

CREATE INDEX idx_boss_destinations_boss ON boss_destinations(boss_id, enabled);
CREATE INDEX idx_message_deliveries_message ON message_deliveries(message_id);
CREATE INDEX idx_message_deliveries_retry ON message_deliveries(status, next_attempt_at);
CREATE UNIQUE INDEX idx_message_deliveries_target ON message_deliveries(message_id, external_target);
CREATE INDEX idx_message_deliveries_merged ON message_deliveries(merged_into);

-- Queued API sends used to come from either an API configuration or the native fallback.
UPDATE delivery_queue SET config = '{"native_only":true}'
WHERE channel = 'api' AND status != 'delivered';

-- Retire unprocessed chat sends without changing stored messages.
UPDATE delivery_queue
SET status = 'failed', attempts = MAX(attempts, 3), error = 'channel removed', config = '{}'
WHERE channel IN ('discord', 'telegram') AND status != 'delivered';

UPDATE delivery_queue SET config = '{}' WHERE channel IN ('discord', 'telegram') AND status = 'delivered';
