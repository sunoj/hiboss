-- CLI-selected names distinguish sessions with the same project label.
-- Nullable and unconstrained so older Workers can continue writing sessions.
ALTER TABLE sessions ADD COLUMN nickname TEXT;
CREATE INDEX idx_sessions_project_nickname ON sessions(project_id, nickname);
