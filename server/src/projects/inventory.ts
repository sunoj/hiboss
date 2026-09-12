// Reads canonical project inventories within an agent visibility scope.
// Exports lookupProject and listProjects; depends on D1 and project identity types.
import type { Project } from './index';

export interface ProjectInventory extends Project {
  display_name: string;
  repo_url: string | null;
  aliases: string[];
  session_count: number;
  last_seen_at: string | null;
  last_post_at: string | null;
}

export async function lookupProject(db: D1Database, name: string): Promise<Project | null> {
  return db.prepare(`SELECT id, slug FROM projects WHERE slug = ? OR id =
    (SELECT project_id FROM project_aliases WHERE alias = ?)`).bind(name, name).first<Project>();
}

export async function listProjects(db: D1Database, agentIds: string[], admin = false): Promise<ProjectInventory[]> {
  const ph = agentIds.map(() => '?').join(', ') || 'NULL';
  const rows = await db.prepare(`WITH visible_sessions AS (
      SELECT * FROM sessions WHERE agent_id IN (${ph})
    ), visible_posts AS (SELECT * FROM progress_posts WHERE agent_id IN (${ph}))
    SELECT p.id, p.slug, p.display_name, p.repo_url,
      (SELECT json_group_array(alias) FROM (SELECT alias FROM project_aliases WHERE project_id = p.id ORDER BY alias)) AS aliases,
      (SELECT COUNT(*) FROM visible_sessions WHERE project_id = p.id) AS session_count,
      (SELECT MAX(last_seen_at) FROM visible_sessions WHERE project_id = p.id) AS last_seen_at,
      (SELECT MAX(created_at) FROM visible_posts WHERE project_id = p.id) AS last_post_at
    FROM projects p WHERE ? OR p.created_by_agent_id IN (${ph})
      OR EXISTS (SELECT 1 FROM visible_sessions WHERE project_id = p.id)
      OR EXISTS (SELECT 1 FROM visible_posts WHERE project_id = p.id)
    ORDER BY p.slug`).bind(...agentIds, ...agentIds, admin ? 1 : 0, ...agentIds)
    .all<Omit<ProjectInventory, 'aliases'> & { aliases: string }>();
  return rows.results.map(row => ({ ...row, aliases: JSON.parse(row.aliases) as string[] }));
}
