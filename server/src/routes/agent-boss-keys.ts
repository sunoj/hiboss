// The public signing keys of every boss who can read this agent, for local pinning by the agent.
// Exports agentBossKeysRouter (GET /api/agents/me/boss-keys). The server is a directory here,
// not a trust anchor: agents pin what this returns and verify later messages against the pins.
// Dependencies: Hono, apiAuth, and D1 tables bosses, boss_agent_access, boss_signing_keys, boss_clients.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

interface BossKeyRow {
  boss_id: string;
  boss_name: string;
  key_id: string | null;
  public_key: string | null;
  client_kind: string | null;
  label: string | null;
  created_at: string | null;
  revoked_at: string | null;
}

export interface BossKeyView {
  key_id: string;
  public_key: string;
  client_kind: string;
  label: string | null;
  created_at: string;
  revoked_at: string | null;
}

export interface BossKeysView {
  boss_id: string;
  name: string;
  keys: BossKeyView[];
}

export const agentBossKeysRouter = new Hono<{ Bindings: Env }>();
agentBossKeysRouter.use('*', apiAuth);

agentBossKeysRouter.get('/', async c => {
  const rows = await c.env.DB.prepare(`SELECT b.id AS boss_id, b.name AS boss_name, k.id AS key_id,
      k.public_key, k.client_kind, cl.label, k.created_at, k.revoked_at
    FROM bosses b
    LEFT JOIN boss_signing_keys k ON k.boss_id = b.id
    LEFT JOIN boss_clients cl ON cl.id = k.client_id
    WHERE b.archived_at IS NULL
      AND (b.role = 'admin' OR b.id IN (SELECT boss_id FROM boss_agent_access WHERE agent_id = ?))
    ORDER BY b.id, k.created_at`).bind(getAgentId(c)).all<BossKeyRow>();
  c.header('Cache-Control', 'no-store');
  return c.json({ bosses: groupByBoss(rows.results ?? []) });
});

/** One entry per boss; a boss with no signing key yet still appears, with no keys. */
export function groupByBoss(rows: BossKeyRow[]): BossKeysView[] {
  const bosses = new Map<string, BossKeysView>();
  for (const row of rows) {
    const boss = bosses.get(row.boss_id) ?? { boss_id: row.boss_id, name: row.boss_name, keys: [] };
    bosses.set(row.boss_id, boss);
    if (row.key_id && row.public_key && row.client_kind && row.created_at) {
      boss.keys.push({
        key_id: row.key_id, public_key: row.public_key, client_kind: row.client_kind,
        label: row.label, created_at: row.created_at, revoked_at: row.revoked_at,
      });
    }
  }
  return [...bosses.values()];
}
