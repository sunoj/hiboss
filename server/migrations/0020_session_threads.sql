-- Add discord_thread_id column to sessions table for per-session thread isolation
ALTER TABLE sessions ADD COLUMN discord_thread_id TEXT;
CREATE INDEX IF NOT EXISTS idx_sessions_discord_thread ON sessions(discord_thread_id) WHERE discord_thread_id IS NOT NULL;
