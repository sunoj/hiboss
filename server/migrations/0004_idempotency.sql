ALTER TABLE messages ADD COLUMN idempotency_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_idempotency ON messages(agent_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
