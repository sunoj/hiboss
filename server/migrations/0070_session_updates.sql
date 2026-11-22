-- Session delta sync: every change stamps updated_at and every removal leaves a row, so clients
-- fetch only what changed since their cursor. Statements are separated by a blank line.
ALTER TABLE sessions ADD COLUMN updated_at TEXT;

UPDATE sessions SET updated_at = last_seen_at;

CREATE INDEX idx_sessions_agent_updated ON sessions(agent_id, updated_at);

CREATE TABLE session_removals (
  session_id TEXT PRIMARY KEY,
  agent_id TEXT NOT NULL,
  removed_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_session_removals_removed ON session_removals(removed_at);

-- ADD COLUMN cannot default to datetime('now'), so inserts are stamped here.
CREATE TRIGGER sessions_inserted_at
AFTER INSERT ON sessions
BEGIN
  UPDATE sessions SET updated_at = datetime('now') WHERE id = NEW.id AND NEW.updated_at IS NULL;
  DELETE FROM session_removals WHERE session_id = NEW.id;
END;

-- Explicit timestamp changes are preserved; the inner guard prevents recursion.
CREATE TRIGGER sessions_updated_at
AFTER UPDATE ON sessions
WHEN NEW.updated_at IS OLD.updated_at
BEGIN
  UPDATE sessions SET updated_at = datetime('now')
  WHERE id = NEW.id AND updated_at IS NOT datetime('now');
END;

CREATE TRIGGER sessions_removed
AFTER DELETE ON sessions
BEGIN
  INSERT OR REPLACE INTO session_removals (session_id, agent_id) VALUES (OLD.id, OLD.agent_id);
END;

-- Listed sessions carry their project's identity and agent name; renames must reach the delta.
CREATE TRIGGER projects_identity_updated
AFTER UPDATE OF slug, display_name, avatar_url ON projects
BEGIN
  UPDATE sessions SET updated_at = datetime('now') WHERE project_id = NEW.id;
END;

CREATE TRIGGER agents_name_updated
AFTER UPDATE OF name ON api_keys
WHEN NEW.name IS NOT OLD.name
BEGIN
  UPDATE sessions SET updated_at = datetime('now') WHERE agent_id = NEW.id;
END;
