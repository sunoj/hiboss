-- Records Box item authorship and isolates retry keys by author.
-- Existing boss items and their retry table remain unchanged.
ALTER TABLE box_items ADD COLUMN agent_id TEXT REFERENCES api_keys(id);

CREATE TABLE box_agent_idempotency (
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  idempotency_key TEXT NOT NULL,
  item_id TEXT NOT NULL,
  PRIMARY KEY (boss_id, agent_id, idempotency_key)
);
