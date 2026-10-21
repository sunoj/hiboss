-- Stores revocable public Box capabilities as hashes only.
-- Shares disappear when their referenced item is physically deleted.
CREATE TABLE box_shares (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES box_items(id) ON DELETE CASCADE,
  boss_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_by_agent TEXT,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT,
  view_count INTEGER NOT NULL DEFAULT 0,
  last_viewed_at TEXT
);
CREATE INDEX idx_box_shares_item ON box_shares(item_id);
