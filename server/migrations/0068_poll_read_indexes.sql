-- Lets the boss feed stream seek its target_agent_id branch by updated_at; that branch
-- previously visited every message addressed to the scoped agents on each 3 s poll.
-- idx_messages_target (target_agent_id, created_at) stays: the agent stream range-seeks it.
CREATE INDEX idx_messages_target_updated
  ON messages(target_agent_id, updated_at, id) WHERE target_agent_id IS NOT NULL;
