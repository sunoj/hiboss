-- Immutable panel metadata and definition revisions for panel publication.
-- Publication is agent-scoped by idempotency key; definitions are append-only by revision.
-- Depends on api_keys, bosses, and sessions from earlier migrations.
CREATE TABLE IF NOT EXISTS panels (
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
  UNIQUE(agent_id, idempotency_key)
);

CREATE INDEX IF NOT EXISTS idx_panels_agent_created ON panels(agent_id, created_at DESC, panel_id DESC);
CREATE INDEX IF NOT EXISTS idx_panels_boss_created ON panels(target_boss_id, created_at DESC, panel_id DESC);

CREATE TABLE IF NOT EXISTS panel_definitions (
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
