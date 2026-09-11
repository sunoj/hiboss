// Shared boss agent access lookup for authenticated API routes.
// Exports getAccessibleAgentIds; depends only on D1 bindings.
import type { Env } from '../types';

/** Get all agent IDs this boss has access to. Admin = all agents. */
export async function getAccessibleAgentIds(env: Env, bossId: string, role: string): Promise<string[]> {
  if (role === 'admin') {
    const rows = await env.DB.prepare('SELECT id FROM api_keys').all<{ id: string }>();
    return (rows.results ?? []).map((r) => r.id);
  }
  const rows = await env.DB
    .prepare('SELECT agent_id FROM boss_agent_access WHERE boss_id = ?')
    .bind(bossId)
    .all<{ agent_id: string }>();
  return (rows.results ?? []).map((r) => r.agent_id);
}
