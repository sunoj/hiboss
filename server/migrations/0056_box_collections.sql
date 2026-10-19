-- Adds boss-owned collections and an idempotent like timestamp to Box items.
-- Memberships survive soft deletion and cascade on physical deletion.
ALTER TABLE box_items ADD COLUMN liked_at TEXT;
CREATE INDEX idx_box_items_liked ON box_items(boss_id, deleted_at, liked_at);
CREATE TABLE box_collections (
  id TEXT PRIMARY KEY,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  name TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_box_collections_name ON box_collections(boss_id, name COLLATE NOCASE);
CREATE TABLE box_collection_items (
  collection_id TEXT NOT NULL REFERENCES box_collections(id) ON DELETE CASCADE,
  item_id TEXT NOT NULL REFERENCES box_items(id) ON DELETE CASCADE,
  added_at TEXT NOT NULL,
  PRIMARY KEY (collection_id, item_id)
);
CREATE INDEX idx_box_collection_items_item ON box_collection_items(item_id);
