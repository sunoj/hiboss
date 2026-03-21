-- Add expires_at column for time-based options expiry sweep.
ALTER TABLE messages ADD COLUMN expires_at TEXT;
CREATE INDEX idx_messages_expires_at ON messages(expires_at) WHERE expires_at IS NOT NULL;
