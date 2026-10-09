-- Records Box item authorship and isolates retry keys by author.
-- Existing items and retry records retain boss authorship.
ALTER TABLE box_items ADD COLUMN agent_id TEXT REFERENCES api_keys(id);

CREATE TABLE box_idempotency_author (
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  author TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT NOT NULL,
  item_id TEXT NOT NULL,
  PRIMARY KEY (boss_id, author, idempotency_key)
);
INSERT INTO box_idempotency_author (boss_id, idempotency_key, item_id)
  SELECT boss_id, idempotency_key, item_id FROM box_idempotency;
DROP TABLE box_idempotency;
ALTER TABLE box_idempotency_author RENAME TO box_idempotency;
