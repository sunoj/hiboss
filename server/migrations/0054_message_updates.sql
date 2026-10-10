-- Track all message updates, including writes that only change metadata.
-- Explicit timestamp changes are preserved; the inner guard prevents recursion.
CREATE TRIGGER messages_updated_at
AFTER UPDATE ON messages
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE messages SET updated_at = datetime('now')
  WHERE id = NEW.id AND updated_at <> datetime('now');
END;

CREATE INDEX idx_messages_agent_updated ON messages(agent_id, updated_at, id);
