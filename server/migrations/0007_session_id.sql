-- Add session_id column for per-session message isolation.
-- Messages sent with a session_id are only visible to that session's inbox.
ALTER TABLE messages ADD COLUMN session_id TEXT;
CREATE INDEX idx_messages_session ON messages(session_id) WHERE session_id IS NOT NULL;
