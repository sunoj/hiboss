-- Boss-owned reference items, retry records and full-text search.
-- Search triggers index only live items and follow metadata edits and deletion.
CREATE TABLE box_items (
  id TEXT PRIMARY KEY,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  kind TEXT NOT NULL CHECK (kind IN ('link', 'text', 'image', 'video', 'file')),
  text TEXT,
  url TEXT,
  note TEXT,
  media_key TEXT,
  media_type TEXT,
  media_bytes INTEGER,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  project TEXT,
  tags TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(tags) AND json_type(tags) = 'array'),
  source TEXT NOT NULL CHECK (source IN ('ios-share', 'mac-share', 'mac-drop', 'cli')),
  created_at TEXT NOT NULL,
  deleted_at TEXT
);
CREATE INDEX idx_box_items_boss_created ON box_items(boss_id, deleted_at, created_at DESC, id DESC);
CREATE TABLE box_idempotency (
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  idempotency_key TEXT NOT NULL,
  item_id TEXT NOT NULL,
  PRIMARY KEY (boss_id, idempotency_key)
);
CREATE VIRTUAL TABLE box_items_fts USING fts5(text, note, url, tags);
CREATE TRIGGER box_items_fts_insert AFTER INSERT ON box_items BEGIN
  INSERT INTO box_items_fts(rowid, text, note, url, tags)
    SELECT new.rowid, new.text, new.note, new.url, new.tags WHERE new.deleted_at IS NULL;
END;
CREATE TRIGGER box_items_fts_update AFTER UPDATE ON box_items BEGIN
  DELETE FROM box_items_fts WHERE rowid = old.rowid;
  INSERT INTO box_items_fts(rowid, text, note, url, tags)
    SELECT new.rowid, new.text, new.note, new.url, new.tags WHERE new.deleted_at IS NULL;
END;
CREATE TRIGGER box_items_fts_delete AFTER DELETE ON box_items BEGIN
  DELETE FROM box_items_fts WHERE rowid = old.rowid;
END;
