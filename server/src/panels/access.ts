// Shared panel access policy: admins see every agent; other roles need explicit grants.
// Exports bossCanAccessAgent and bossPanelScope, matching getAccessibleAgentIds semantics.
// Dependencies: D1, Hono boss identity helpers.
import type { Context } from 'hono';
import type { Env } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';

export async function bossCanAccessAgent(db: D1Database, bossId: string, agentId: string): Promise<boolean> {
  const row = await db.prepare(`SELECT 1 FROM bosses b WHERE b.id = ? AND
    (b.role = 'admin' OR EXISTS (SELECT 1 FROM boss_agent_access a WHERE a.boss_id = b.id AND a.agent_id = ?))`)
    .bind(bossId, agentId).first();
  return row !== null;
}

export function bossPanelScope(c: Context<{ Bindings: Env }>): { sql: string; binds: string[] } {
  if (getBossRole(c) === 'admin') return { sql: '1 = 1', binds: [] };
  const bossId = getBossId(c);
  return { sql: 'p.target_boss_id = ? AND EXISTS (SELECT 1 FROM boss_agent_access ba WHERE ba.boss_id = ? AND ba.agent_id = p.agent_id)', binds: [bossId, bossId] };
}

// Keep mutation-time permission checks aligned with preflight authorization.
export function panelTargetAccessSql(table: 'p' | 'panels'): string {
  return `EXISTS (SELECT 1 FROM bosses b WHERE b.id = ${table}.target_boss_id AND
    (b.role = 'admin' OR EXISTS (SELECT 1 FROM boss_agent_access ba
      WHERE ba.boss_id = b.id AND ba.agent_id = ${table}.agent_id)))`;
}
