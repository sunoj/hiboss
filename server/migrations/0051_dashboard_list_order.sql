-- Bound each accessible agent's ordered page, including same-second messages.
-- Keep the status index for selective filters and avoid indexing session heartbeats.
CREATE INDEX idx_messages_agent_page ON messages(agent_id, created_at DESC, id DESC);
CREATE INDEX idx_messages_boss_page ON messages(agent_id, created_at DESC, id DESC)
  WHERE direction = 'agent_to_boss';
