-- Cuts D1 read amplification in the boss SSE polling loops.
-- The option stream filtered on expires_at after seeking idx_messages_status, visiting every
-- historical agent_to_boss/read row per poll; the feed stream's OR branch on target_agent_id had
-- no created_at column, visiting every agent_to_agent row per poll.
CREATE INDEX idx_messages_agent_expires
  ON messages(agent_id, expires_at) WHERE expires_at IS NOT NULL;

DROP INDEX idx_messages_target;
CREATE INDEX idx_messages_target
  ON messages(target_agent_id, created_at) WHERE target_agent_id IS NOT NULL;
