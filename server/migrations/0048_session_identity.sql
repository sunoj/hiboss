-- Session identity: where a session runs and, for a dispatched session, the
-- session that dispatched it. parent_session_id is stored only after the server
-- checks that the parent's agent is on the caller's device; it has no foreign
-- key so that deleting a parent session leaves its children readable.
ALTER TABLE sessions ADD COLUMN host TEXT;
ALTER TABLE sessions ADD COLUMN runtime TEXT;
ALTER TABLE sessions ADD COLUMN dispatch_ref TEXT;
ALTER TABLE sessions ADD COLUMN parent_session_id TEXT;
CREATE INDEX idx_sessions_parent ON sessions(parent_session_id) WHERE parent_session_id IS NOT NULL;
