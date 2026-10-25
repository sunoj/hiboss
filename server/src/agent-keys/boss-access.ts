// Who may administer an agent's credentials, and the sweep that retires boss-minted keys.
// Exports bossKeyAccess middleware, the minting predicate and mintedKeySweep statements.
// Managers never reach boss-linked or is_admin agents: those keys open admin-scoped surfaces.
import type { Context, Next } from 'hono';
import type { Env } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';
import { getAccessibleAgentIds } from '../routes/boss-api-access';

/** SQL true when agent `agent` carries more than its own scope (a boss identity or is_admin). */
const protectedAgent = (agent: string) => `(EXISTS (SELECT 1 FROM bosses linked WHERE linked.agent_id = ${agent})
  OR EXISTS (SELECT 1 FROM api_keys capable WHERE capable.id = ${agent} AND capable.is_admin = 1))`;

/** SQL true when boss `boss` may still mint keys for agent `agent`. */
export const mayMint = (boss: string, agent: string) => `EXISTS (SELECT 1 FROM bosses minter
  WHERE minter.id = ${boss} AND minter.archived_at IS NULL AND (minter.role = 'admin' OR (minter.role = 'manager'
    AND EXISTS (SELECT 1 FROM boss_agent_access g WHERE g.boss_id = minter.id AND g.agent_id = ${agent})
    AND NOT ${protectedAgent(agent)})))`;

const orphaned = `revoked_at IS NULL AND minted_by_boss_id IS NOT NULL
  AND NOT ${mayMint('agent_keys.minted_by_boss_id', 'agent_keys.agent_id')}`;

/** Audits then revokes every live key whose minting boss lost the right to mint it. Append to the changing batch. */
export function mintedKeySweep(db: D1Database): D1PreparedStatement[] {
  return [
    db.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
      SELECT 'system', 'boss-access', 'agent_key.revoke', 'agent_key', id,
        json_object('agent_id', agent_id, 'minted_by_boss_id', minted_by_boss_id) FROM agent_keys WHERE ${orphaned}`),
    db.prepare(`UPDATE agent_keys SET revoked_at = datetime('now') WHERE ${orphaned}`),
  ];
}

export async function bossKeyAccess(c: Context<{ Bindings: Env }>, next: Next): Promise<Response | void> {
  const role = getBossRole(c);
  if (role !== 'admin' && role !== 'manager') return c.text('admin or manager required', 403);
  const agentId = c.req.param('agentId') ?? '';
  const ids = await getAccessibleAgentIds(c.env, getBossId(c), role);
  if (!ids.includes(agentId)) return c.text('not found', 404);
  const allowed = await c.env.DB.prepare(`SELECT ${mayMint('?1', '?2')} AS ok`).bind(getBossId(c), agentId).first<number>('ok');
  if (allowed !== 1) return c.text('admin required for a boss-linked or admin-capable agent', 403);
  await next();
}
