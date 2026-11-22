// Boss session inventory: full lists with a cursor, deltas since a cursor, and row hydration.
// Exports listSessions and mapSessionList; depends on D1 and the shared project response mapping.
import { mapSessionProject } from '../projects/session-label';
import { validMessageCursor } from './boss-message-history';

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

/** A delta cursor: the D1 time it was read, plus a digest of the agents the boss could see then. */
export interface SessionCursor { at: string; access: string }

export function parseSessionCursor(value: string): SessionCursor | null {
  const [at, access, extra] = value.split('~');
  return extra === undefined && access && /^[0-9a-f]{16}$/.test(access) && validMessageCursor(at) ? { at, access } : null;
}

/** Access changes are invisible to a delta, so a cursor issued for another agent set is refused. */
export async function accessDigest(agentIds: string[]): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode([...agentIds].sort().join('\n')));
  return [...new Uint8Array(digest).slice(0, 8)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

/**
 * Lists the agents' sessions. With `since` (from an earlier cursor), only sessions changed or
 * removed at or after it; the new cursor is read before the rows, so nothing is skipped.
 */
export async function listSessions(db: D1Database, agentIds: string[], inactive: boolean,
  since?: string): Promise<SessionInventory> {
  const access = await accessDigest(agentIds);
  const clock = db.prepare("SELECT datetime('now') AS cursor");
  const placeholders = agentIds.map(() => '?').join(', ');
  const live = inactive ? '' : "AND s.last_seen_at > datetime('now', '-15 minutes')";
  const reads = agentIds.length === 0 ? [] : since === undefined
    ? [db.prepare(`SELECT s.* FROM sessions s WHERE s.agent_id IN (${placeholders}) ${live} ORDER BY s.last_seen_at DESC`)
      .bind(...agentIds)]
    : [db.prepare(`SELECT s.* FROM sessions s INDEXED BY idx_sessions_agent_updated
        WHERE s.agent_id IN (${placeholders}) AND s.updated_at >= ? ORDER BY s.updated_at, s.id`)
      .bind(...agentIds, since),
    db.prepare(`SELECT session_id FROM session_removals WHERE removed_at >= ?
        AND agent_id IN (${placeholders}) ORDER BY removed_at, session_id`).bind(since, ...agentIds)];
  const [now, rows, removed] = await db.batch<unknown>([clock, ...reads]);
  const sessions = await mapSessionList(db, (rows?.results ?? []) as ListedSession[]);
  const cursor = `${cursorOf(now)}~${access}`;
  if (since === undefined) return { sessions, cursor };
  return { sessions, removed: ((removed?.results ?? []) as { session_id: string }[]).map(row => row.session_id), cursor };
}

function cursorOf(result: D1Result<unknown>): string {
  const cursor = (result.results[0] as { cursor?: string } | undefined)?.cursor;
  if (!cursor) throw new Error('D1 session clock unavailable');
  return cursor;
}
