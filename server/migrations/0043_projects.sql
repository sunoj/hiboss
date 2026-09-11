-- Project identities and aliases; legacy text and messages are preserved.
-- Duplicate agent names abort before changing the entity model.
CREATE TABLE _project_name_guard (
  count INTEGER CONSTRAINT duplicate_api_keys_names CHECK (count = 0)
);
INSERT INTO _project_name_guard SELECT COUNT(*) FROM (
  SELECT name FROM api_keys GROUP BY name HAVING COUNT(*) > 1
);
DROP TABLE _project_name_guard;
CREATE UNIQUE INDEX idx_api_keys_name ON api_keys(name);

CREATE TABLE projects (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  slug TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  repo_url TEXT,
  handle TEXT UNIQUE,
  bio TEXT,
  avatar_url TEXT,
  created_by_agent_id TEXT REFERENCES api_keys(id),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE project_aliases (
  alias TEXT PRIMARY KEY NOT NULL,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('origin', 'cwd', 'explicit', 'label')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_project_aliases_project ON project_aliases(project_id);
ALTER TABLE sessions ADD COLUMN project_id TEXT REFERENCES projects(id);
ALTER TABLE progress_posts ADD COLUMN project_id TEXT REFERENCES projects(id);
ALTER TABLE destination_routes ADD COLUMN project_id TEXT REFERENCES projects(id);
CREATE INDEX idx_sessions_project ON sessions(project_id);
CREATE INDEX idx_progress_project_id ON progress_posts(project_id, created_at DESC, id DESC);
CREATE INDEX idx_destination_routes_project ON destination_routes(project_id);

CREATE TABLE _project_sources (value TEXT PRIMARY KEY, source TEXT NOT NULL, slug TEXT, base TEXT);
INSERT INTO _project_sources (value, source)
SELECT project, 'explicit' FROM progress_teams WHERE trim(project) != ''
UNION SELECT project, 'explicit' FROM progress_posts WHERE trim(project) != '';
INSERT OR IGNORE INTO _project_sources (value, source)
SELECT CASE WHEN instr(label, '/') > 0 THEN substr(label, 1, instr(label, '/') - 1) ELSE label END, 'label'
FROM sessions WHERE trim(CASE WHEN instr(label, '/') > 0 THEN substr(label, 1, instr(label, '/') - 1) ELSE label END) != '';

-- Normalize ASCII URL-safe slugs, collapsing punctuation runs into one dash.
WITH RECURSIVE normalized(value, rest, slug) AS (
  SELECT value, lower(trim(value)), '' FROM _project_sources
  UNION ALL
  SELECT value, substr(rest, 2), slug || CASE
    WHEN substr(rest, 1, 1) GLOB '[a-z0-9_]' THEN substr(rest, 1, 1)
    WHEN substr(slug, -1) = '-' THEN '' ELSE '-' END
  FROM normalized WHERE rest != ''
)
UPDATE _project_sources SET slug = (SELECT trim(slug, '-') FROM normalized n WHERE n.value = _project_sources.value AND rest = '');
UPDATE _project_sources SET base = slug;
-- Double dash is reserved for collision suffixes; normalized bases cannot contain it.
UPDATE _project_sources SET slug = CASE WHEN slug = '' THEN 'project' ELSE slug END || '--' || lower(hex(value))
WHERE slug = '' OR slug IN (SELECT slug FROM _project_sources GROUP BY slug HAVING COUNT(*) > 1);
-- Keep generated identities usable through the same 256-character API boundary.
UPDATE _project_sources SET slug = 'project--' || lower(hex(randomblob(16))) WHERE length(slug) > 256;
INSERT INTO projects (slug, display_name, handle, bio, avatar_url, created_by_agent_id, created_at, updated_at)
SELECT s.slug, COALESCE(t.display_name, s.value), t.handle, t.bio, t.avatar_url, t.created_by_agent_id,
  COALESCE(t.created_at, datetime('now')), COALESCE(t.updated_at, datetime('now'))
FROM _project_sources s LEFT JOIN progress_teams t ON t.project = s.value;
INSERT INTO project_aliases (alias, project_id, source)
SELECT s.value, p.id, s.source FROM _project_sources s JOIN projects p ON p.slug = s.slug;
-- Every generated slug is itself an alias, including absorbed collision slugs.
INSERT OR IGNORE INTO project_aliases (alias, project_id, source)
SELECT slug, id, 'explicit' FROM projects;
INSERT OR IGNORE INTO project_aliases (alias, project_id, source)
SELECT s.base, p.id, 'explicit' FROM _project_sources s JOIN projects p ON p.slug = s.slug
WHERE s.base != '' ORDER BY s.value;
UPDATE sessions SET project_id = (SELECT project_id FROM project_aliases WHERE alias =
  CASE WHEN instr(sessions.label, '/') > 0 THEN substr(sessions.label, 1, instr(sessions.label, '/') - 1) ELSE sessions.label END);
UPDATE progress_posts SET project_id = (SELECT project_id FROM project_aliases WHERE alias = progress_posts.project);
UPDATE destination_routes SET project_id = COALESCE(
  (SELECT project_id FROM project_aliases WHERE alias = destination_routes.project),
  (SELECT project_id FROM sessions WHERE id = destination_routes.session_id));

-- Reconcile normalized spellings and origin/checkout pairs evidenced by one agent.
CREATE TABLE _project_edges (origin TEXT, checkout TEXT, historical INTEGER);
-- A historical literal alias may itself spell another generated canonical slug.
INSERT INTO _project_edges
SELECT p.id, a.project_id, 0 FROM projects p JOIN project_aliases a ON a.alias = p.slug WHERE p.id != a.project_id;
INSERT INTO _project_edges
SELECT a.project_id, b.project_id, 0 FROM _project_sources x
JOIN _project_sources y ON x.base = y.base AND x.value < y.value AND x.base != ''
JOIN project_aliases a ON a.alias = x.value JOIN project_aliases b ON b.alias = y.value;
WITH RECURSIVE paths(id, agent_id, project_id, rest) AS (
  SELECT id, agent_id, project_id, rtrim(replace(cwd, char(92), '/'), '/') FROM sessions WHERE cwd IS NOT NULL
  UNION ALL
  SELECT id, agent_id, project_id, substr(rest, instr(rest, '/') + 1) FROM paths WHERE instr(rest, '/') > 0
)
INSERT INTO _project_edges
SELECT DISTINCT s.project_id, p.project_id, 1 FROM paths s
JOIN progress_posts p ON p.agent_id = s.agent_id AND p.project = s.rest
WHERE instr(s.rest, '/') = 0 AND s.rest != '' AND s.project_id IS NOT NULL
  AND p.project_id IS NOT NULL AND s.project_id != p.project_id;
-- Connected components absorb transitive rename history in a single migration.
CREATE TABLE _project_merges (absorbed TEXT PRIMARY KEY, winner TEXT NOT NULL);
WITH RECURSIVE connected(member, candidate) AS (
  SELECT id, id FROM projects
  UNION
  SELECT c.member, CASE WHEN e.origin = c.candidate THEN e.checkout ELSE e.origin END
  FROM connected c JOIN _project_edges e ON c.candidate IN (e.origin, e.checkout)
), ranked AS (
  SELECT c.member, c.candidate, row_number() OVER (PARTITION BY c.member ORDER BY
    EXISTS(SELECT 1 FROM _project_edges e WHERE e.origin = c.candidate AND e.historical = 1) DESC,
    p.created_at, p.slug, p.id) AS rank
  FROM connected c JOIN projects p ON p.id = c.candidate
)
INSERT INTO _project_merges SELECT member, candidate FROM ranked WHERE rank = 1 AND member != candidate;
INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
SELECT 'system', 'migration:0043', 'project.merge', 'project', winner,
  json_object('absorbed_ids', json_group_array(absorbed)) FROM _project_merges GROUP BY winner;
UPDATE sessions SET project_id = (SELECT winner FROM _project_merges WHERE absorbed = project_id)
WHERE project_id IN (SELECT absorbed FROM _project_merges);
UPDATE progress_posts SET project_id = (SELECT winner FROM _project_merges WHERE absorbed = project_id)
WHERE project_id IN (SELECT absorbed FROM _project_merges);
UPDATE destination_routes SET project_id = (SELECT winner FROM _project_merges WHERE absorbed = project_id)
WHERE project_id IN (SELECT absorbed FROM _project_merges);
UPDATE project_aliases SET project_id = (SELECT winner FROM _project_merges WHERE absorbed = project_id)
WHERE project_id IN (SELECT absorbed FROM _project_merges);
DELETE FROM projects WHERE id IN (SELECT absorbed FROM _project_merges);
DROP TABLE _project_merges;
DROP TABLE _project_edges;
DROP TABLE _project_sources;
