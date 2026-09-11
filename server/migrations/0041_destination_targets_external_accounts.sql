-- Persist one claim per effective target while retaining boss delivery attribution.
-- Add external identities without altering messages or legacy delivery tables.
ALTER TABLE message_deliveries ADD COLUMN external_target TEXT;
ALTER TABLE message_deliveries ADD COLUMN merged_into TEXT REFERENCES message_deliveries(id) ON DELETE CASCADE;
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
INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id)
SELECT id, 'telegram', telegram_user_id FROM bosses WHERE telegram_user_id IS NOT NULL AND telegram_user_id != '';
INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id)
SELECT id, 'discord', discord_user_id FROM bosses WHERE discord_user_id IS NOT NULL AND discord_user_id != '';
