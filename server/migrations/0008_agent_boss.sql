-- Add agent_id to bosses: allows an agent to act as a boss for other agents.
-- Messages to agent-bosses use channel='api' (no external delivery needed).
ALTER TABLE bosses ADD COLUMN agent_id TEXT REFERENCES api_keys(id);
CREATE UNIQUE INDEX idx_bosses_agent ON bosses(agent_id) WHERE agent_id IS NOT NULL;

-- Allow 'api' as a valid channel for messages between agents.
-- D1 doesn't support ALTER CHECK constraints, so we drop and recreate.
-- However, D1 ALTER TABLE is limited — we handle this at application level instead.
-- The CHECK constraint on messages.channel allows NULL already, and we validate in code.
