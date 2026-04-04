-- Add telegram_topic_id column to sessions table for per-session Telegram topic isolation
ALTER TABLE sessions ADD COLUMN telegram_topic_id INTEGER;
CREATE INDEX idx_sessions_telegram_topic ON sessions(telegram_topic_id) WHERE telegram_topic_id IS NOT NULL;
