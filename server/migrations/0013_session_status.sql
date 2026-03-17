-- Add status tracking to sessions for work state visibility.
-- status: working, blocked, waiting, idle, completed
-- status_text: brief description of current activity

ALTER TABLE sessions ADD COLUMN status TEXT NOT NULL DEFAULT 'working' CHECK (status IN ('working', 'blocked', 'waiting', 'idle', 'completed'));
ALTER TABLE sessions ADD COLUMN status_text TEXT;
