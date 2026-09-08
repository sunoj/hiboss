-- Durable panel outcomes and boss-owned placement, with immutable operation receipts.
-- Extends existing panel records without discarding their definitions or initial data.
-- Dependencies: panels and bosses from existing migrations.
ALTER TABLE panels ADD COLUMN lifecycle_json TEXT NOT NULL DEFAULT '{"taskState":"running","mode":"run","expectedUpdateIntervalSeconds":15,"terminalAt":null,"dismissAt":null,"dismissalPolicy":null,"result":null}';
ALTER TABLE panels ADD COLUMN final_snapshot_json TEXT;
ALTER TABLE panels ADD COLUMN last_operation_id TEXT;
ALTER TABLE panels ADD COLUMN supersedes_panel_id TEXT REFERENCES panels(panel_id);
CREATE TABLE panel_preferences (
  panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,
  boss_id TEXT NOT NULL REFERENCES bosses(id) ON DELETE CASCADE,
  preference_version INTEGER NOT NULL,
  value_json TEXT NOT NULL,
  PRIMARY KEY (panel_id, boss_id)
);
CREATE TABLE panel_operations (
  operation_id TEXT PRIMARY KEY,
  panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,
  agent_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL,
  request_hash TEXT NOT NULL,
  receipt_json TEXT NOT NULL,
  UNIQUE (panel_id, agent_id, idempotency_key)
);
CREATE TABLE panel_outbox (
  event_id TEXT PRIMARY KEY,
  panel_id TEXT NOT NULL REFERENCES panels(panel_id) ON DELETE CASCADE,
  metadata_version INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  delivered_at TEXT
);
