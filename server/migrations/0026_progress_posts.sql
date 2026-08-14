CREATE TABLE IF NOT EXISTS progress_posts (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  session_id TEXT,
  project TEXT NOT NULL,
  body TEXT NOT NULL,
  media TEXT,
  tags TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_progress_created ON progress_posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_progress_project ON progress_posts(project, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_progress_agent ON progress_posts(agent_id, created_at DESC);
