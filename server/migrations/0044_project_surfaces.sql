-- Retire the team snapshot only when every team alias resolves to a project.
-- Project IDs stay SQL-nullable; API writes require a resolvable identity.
CREATE TABLE project_profile_guard (missing_team_project INTEGER CHECK (missing_team_project = 0));
INSERT INTO project_profile_guard SELECT COUNT(*) FROM progress_teams t
WHERE NOT EXISTS (SELECT 1 FROM project_aliases a JOIN projects p ON p.id = a.project_id WHERE a.alias = t.project);
DROP TABLE project_profile_guard;
DROP TABLE progress_teams;

-- Preserve historical text, posts and likes while allowing ID-only new writes.
CREATE TABLE progress_likes_snapshot AS SELECT * FROM progress_likes;
CREATE TABLE progress_posts_next (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  agent_id TEXT NOT NULL REFERENCES api_keys(id),
  session_id TEXT,
  project TEXT,
  body TEXT NOT NULL,
  media TEXT,
  tags TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  agent_label TEXT,
  model TEXT,
  project_id TEXT REFERENCES projects(id)
);

INSERT INTO progress_posts_next SELECT * FROM progress_posts;
DROP TABLE progress_likes;
DROP TABLE progress_posts;
ALTER TABLE progress_posts_next RENAME TO progress_posts;
CREATE INDEX IF NOT EXISTS idx_progress_created ON progress_posts(created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_progress_project ON progress_posts(project, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_progress_agent ON progress_posts(agent_id, created_at DESC, id DESC);

CREATE INDEX idx_progress_project_id ON progress_posts(project_id, created_at DESC, id DESC);
CREATE TABLE IF NOT EXISTS progress_likes (
  post_id TEXT NOT NULL REFERENCES progress_posts(id) ON DELETE CASCADE,
  boss_id TEXT NOT NULL REFERENCES bosses(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (post_id, boss_id)
);

CREATE INDEX IF NOT EXISTS idx_progress_likes_post ON progress_likes(post_id);

INSERT INTO progress_likes SELECT * FROM progress_likes_snapshot;
DROP TABLE progress_likes_snapshot;
-- destination_routes.project and progress_posts.project are removed in a later phase.

-- Canonical route scopes: duplicate historical scopes fail this unique-index guard.
DROP INDEX idx_destination_routes_scope;
CREATE UNIQUE INDEX idx_destination_routes_scope ON destination_routes(destination_id, COALESCE(project_id, ''), COALESCE(session_id, ''));
