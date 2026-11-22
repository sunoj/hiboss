// Boss session inventory: full lists with a cursor, deltas since a cursor, and row hydration.
// Exports listSessions and mapSessionList; depends on D1 and the shared project response mapping.
import { mapSessionProject } from '../projects/session-label';

export interface ListedSession {
  agent_id: string;
  project_id: string | null;
  label: string | null;
  nickname: string | null;
  branch: string | null;
}

export async function mapSessionList(db: D1Database, rows: ListedSession[]) {
  if (rows.length === 0) return [];
  const agentIds = [...new Set(rows.map(row => row.agent_id))];
  const projectIds = [...new Set(rows.flatMap(row => row.project_id ? [row.project_id] : []))];
  const [agents, projects] = await Promise.all([
    db.prepare('SELECT id, name FROM api_keys WHERE id IN (SELECT value FROM json_each(?))')
      .bind(JSON.stringify(agentIds)).all<{ id: string; name: string }>(),
    db.prepare('SELECT id, slug, display_name, avatar_url FROM projects WHERE id IN (SELECT value FROM json_each(?))')
      .bind(JSON.stringify(projectIds))
      .all<{ id: string; slug: string; display_name: string; avatar_url: string | null }>(),
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
      project_avatar_url: project?.avatar_url ?? null,
      label: project ? (branch === '' ? project.slug : `${project.slug}/${branch}`) : row.label,
    });
  });
}

export type SessionInventory = { sessions: ReturnType<typeof mapSessionProject>[]; cursor: string; removed?: string[] };

/**
 * Lists the agents' sessions. With `updatedAfter` (a cursor from an earlier answer), only sessions
 * changed or removed at or after it; the cursor is read before the rows, so nothing is skipped.
 */
export async function listSessions(db: D1Database, agentIds: string[], inactive: boolean,
  updatedAfter?: string): Promise<SessionInventory> {
  const placeholders = agentIds.map(() => '?').join(', ');
  const clock = db.prepare("SELECT datetime('now') AS cursor");
  const live = inactive ? '' : "AND s.last_seen_at > datetime('now', '-15 minutes')";
  if (updatedAfter === undefined) {
    const [now, rows] = await db.batch<unknown>([clock, db.prepare(
      `SELECT s.* FROM sessions s WHERE s.agent_id IN (${placeholders}) ${live} ORDER BY s.last_seen_at DESC`,
    ).bind(...agentIds)]);
    return { sessions: await mapSessionList(db, rows.results as ListedSession[]), cursor: cursorOf(now) };
  }
  const [now, rows, removed] = await db.batch<unknown>([clock,
    db.prepare(`SELECT s.* FROM sessions s INDEXED BY idx_sessions_agent_updated
      WHERE s.agent_id IN (${placeholders}) AND s.updated_at >= ? ORDER BY s.updated_at, s.id`)
      .bind(...agentIds, updatedAfter),
    db.prepare(`SELECT session_id FROM session_removals WHERE removed_at >= ?
      AND agent_id IN (${placeholders}) ORDER BY removed_at, session_id`).bind(updatedAfter, ...agentIds)]);
  return {
    sessions: await mapSessionList(db, rows.results as ListedSession[]),
    removed: (removed.results as { session_id: string }[]).map(row => row.session_id),
    cursor: cursorOf(now),
  };
}

function cursorOf(result: D1Result<unknown>): string {
  const cursor = (result.results[0] as { cursor?: string } | undefined)?.cursor;
  if (!cursor) throw new Error('D1 session clock unavailable');
  return cursor;
}
