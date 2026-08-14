CREATE TABLE IF NOT EXISTS progress_teams (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  project TEXT NOT NULL UNIQUE,
  handle TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  bio TEXT,
  avatar_url TEXT,
  created_by_agent_id TEXT REFERENCES api_keys(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS progress_likes (
  post_id TEXT NOT NULL REFERENCES progress_posts(id) ON DELETE CASCADE,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (post_id, boss_id)
);

CREATE INDEX IF NOT EXISTS idx_progress_likes_post ON progress_likes(post_id);
