// Hydrate session lists with one lookup per distinct agent/project instead of per row.
// Exports mapSessionList; depends on D1 and the shared project response mapping.
import { mapSessionProject } from '../projects/session-label';

export interface ListedSession {
  agent_id: string;
  project_id: string | null;
  label: string | null;
  branch: string | null;
}

export async function mapSessionList(db: D1Database, rows: ListedSession[]) {
  if (rows.length === 0) return [];
  const agentIds = [...new Set(rows.map(row => row.agent_id))];
  const projectIds = [...new Set(rows.flatMap(row => row.project_id ? [row.project_id] : []))];
  const [agents, projects] = await Promise.all([
    db.prepare('SELECT id, name FROM api_keys WHERE id IN (SELECT value FROM json_each(?))')
      .bind(JSON.stringify(agentIds)).all<{ id: string; name: string }>(),
    db.prepare('SELECT id, slug, display_name FROM projects WHERE id IN (SELECT value FROM json_each(?))')
      .bind(JSON.stringify(projectIds)).all<{ id: string; slug: string; display_name: string }>(),
  ]);
  const names = new Map(agents.results.map(agent => [agent.id, agent.name]));
  const identities = new Map(projects.results.map(project => [project.id, project]));
  return rows.map(row => {
    const project = row.project_id ? identities.get(row.project_id) : undefined;
    const slash = row.label?.indexOf('/') ?? -1;
    const branch = row.branch ?? (slash >= 0 ? row.label?.slice(slash + 1) ?? '' : '');
    return mapSessionProject({
      ...row,
      agent_name: names.get(row.agent_id) ?? null,
      project_slug: project?.slug ?? null,
      project_display_name: project?.display_name ?? null,
      label: project ? (branch === '' ? project.slug : `${project.slug}/${branch}`) : row.label,
    });
  });
}
