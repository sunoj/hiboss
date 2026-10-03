// Shared panel access policy: admins see every agent; other roles need explicit grants.
// Exports boss resolution/default selection and panel access checks/scopes.
// Dependencies: D1, Hono boss identity helpers.
import type { Context } from 'hono';
import type { Env } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';

export interface ResolvedBoss {
  id: string;
  name: string;
  role: 'admin' | 'manager' | 'viewer';
}

export async function resolvedBosses(db: D1Database, agentId: string): Promise<ResolvedBoss[]> {
  const rows = await db.prepare(`SELECT b.id, b.name, b.role FROM bosses b
    WHERE b.role = 'admin' OR EXISTS (SELECT 1 FROM boss_agent_access a WHERE a.boss_id = b.id AND a.agent_id = ?)
    ORDER BY (b.role = 'admin') DESC, b.id`).bind(agentId).all<ResolvedBoss>();
  return rows.results ?? [];
}

export function defaultBossId(rows: readonly ResolvedBoss[]): string | null {
  if (rows.length === 1) return rows[0].id;
  const admins = rows.filter(row => row.role === 'admin');
  return admins.length === 1 ? admins[0].id : null;
}

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
