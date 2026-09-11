// CRUD and access management for boss identities.
// Exports bossesRouter mounted at /api/bosses.
// Depends on Hono, auth middleware, and D1 bindings.

import { Hono } from 'hono';
import type { Context } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import { logAudit } from '../audit';
import { identityConflict, legacyIdentityWrites } from './boss-external-accounts';
import { buildBossUpdate } from './boss-updates';
import { issueBossToken } from '../boss-token';

type BossRole = 'admin' | 'manager' | 'viewer';

export interface BossRow {
  id: string;
  name: string;
  role: BossRole;
  telegram_user_id: string | null;
  discord_user_id: string | null;
  agent_id: string | null;
  preferences: string | null;
  created_at: string;
}

interface AgentRow {
  id: string;
  name: string;
}

const VALID_ROLES: BossRole[] = ['admin', 'manager', 'viewer'];

function requireAdmin(c: Context<{ Bindings: Env }>): Response | null {
  if (getBossRole(c) !== 'admin') {
    return c.json({ error: 'admin required' }, 403);
  }
  return null;
}

export function escapeLike(value: string): string {
  return value.replace(/([\\%_])/g, '\\$1');
}

function safeParse(value: string | null): Record<string, unknown> | null {
  if (!value) return null;
  try { return JSON.parse(value) as Record<string, unknown>; } catch { return null; }
}

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);

routes.get('/', async (c) => {
  const rows = await c.env.DB
    .prepare(
      'SELECT b.*, GROUP_CONCAT(ba.agent_id) AS agent_ids FROM bosses b LEFT JOIN boss_agent_access ba ON ba.boss_id = b.id GROUP BY b.id ORDER BY b.created_at DESC'
    )
    .all<BossRow & { agent_ids: string | null }>();
  const bosses = (rows.results ?? []).map((row) => ({
    id: row.id,
    name: row.name,
    role: row.role,
    telegram_user_id: row.telegram_user_id,
    discord_user_id: row.discord_user_id,
    agent_id: row.agent_id,
    preferences: safeParse(row.preferences),
    created_at: row.created_at,
    agent_ids: row.agent_ids ? row.agent_ids.split(',').filter(Boolean) : [],
  }));
  return c.json({ bosses });
});

routes.post('/', async (c) => {
  const denied = requireAdmin(c);
  if (denied) return denied;
  const payload = await c.req.json<Record<string, unknown>>();
  const name = typeof payload.name === 'string' ? payload.name.trim() : '';
  if (!name) {
    return c.text('name is required', 400);
  }
  const role = typeof payload.role === 'string' && VALID_ROLES.includes(payload.role as BossRole) ? (payload.role as BossRole) : 'admin';
  const telegramInput = typeof payload.telegram_user_id === 'string' ? payload.telegram_user_id.trim() : null;
  const telegramUserId = telegramInput === '' ? null : telegramInput;
  const discordInput = typeof payload.discord_user_id === 'string' ? payload.discord_user_id.trim() : null;
  const discordUserId = discordInput === '' ? null : discordInput;
  const agentIdInput = typeof payload.agent_id === 'string' ? payload.agent_id.trim() : null;
  const bossAgentId = agentIdInput === '' ? null : agentIdInput;
  const id = crypto.randomUUID();
  for (const [provider, userId] of [['telegram', telegramUserId], ['discord', discordUserId]] as const) {
    if (userId && await identityConflict(c.env, id, provider, userId)) return c.json({ error: 'external account already linked' }, 409);
  }
  const results = await c.env.DB.batch<BossRow>([
    c.env.DB.prepare('INSERT INTO bosses (id, name, role, telegram_user_id, discord_user_id, agent_id) VALUES (?, ?, ?, ?, ?, ?) RETURNING *')
      .bind(id, name, role, telegramUserId, discordUserId, bossAgentId),
    ...legacyIdentityWrites(c.env, id, 'telegram', null, telegramUserId),
    ...legacyIdentityWrites(c.env, id, 'discord', null, discordUserId),
  ]);
  const inserted = results[0].results[0];
  if (!inserted) {
    return c.text('failed to create boss', 500);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.create', 'boss', inserted.id, JSON.stringify({ name, role })));
  return c.json(inserted, 201);
});

routes.get('/:id', async (c) => {
  const bossId = c.req.param('id');
  const boss = await findBoss(c.env, bossId);
  if (!boss) {
    return c.text('not found', 404);
  }
  const agents = await c.env.DB
    .prepare('SELECT k.id, k.name FROM boss_agent_access ba JOIN api_keys k ON k.id = ba.agent_id WHERE ba.boss_id = ?')
    .bind(boss.id)
    .all<AgentRow>();
  return c.json({ ...boss, preferences: safeParse(boss.preferences), agents: agents.results ?? [] });
});

routes.patch('/:id', async (c) => {
  const denied = requireAdmin(c);
  if (denied) return denied;
  const bossId = c.req.param('id');
  const boss = await findBoss(c.env, bossId);
  if (!boss) {
    return c.text('not found', 404);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const result = await buildBossUpdate(c.env, boss, payload);
  if (!result.ok) return c.json({ error: result.error }, result.status);
  try { await c.env.DB.batch(result.writes); }
  catch (error) {
    if (String(error).includes('UNIQUE constraint failed')) return c.json({ error: 'external account already linked' }, 409);
    throw error;
  }
  const updated = await findBoss(c.env, boss.id);
  if (!updated) {
    return c.text('not found', 404);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.update', 'boss', boss.id, JSON.stringify(Object.keys(payload))));
  return c.json(updated);
});

routes.delete('/:id', async (c) => {
  const denied = requireAdmin(c);
  if (denied) return denied;
  const bossId = c.req.param('id');
  const result = await c.env.DB
    .prepare('DELETE FROM bosses WHERE id = ?')
    .bind(bossId)
    .run();
  if (!result.meta.changes || result.meta.changes === 0) {
    return c.text('not found', 404);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.delete', 'boss', bossId));
  return c.json({ ok: true });
});

routes.post('/:id/access', async (c) => {
  const denied = requireAdmin(c);
  if (denied) return denied;
  const bossId = c.req.param('id');
  const boss = await findBoss(c.env, bossId);
  if (!boss) {
    return c.text('boss not found', 404);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const agentId = typeof payload.agent_id === 'string' ? payload.agent_id : '';
  if (!agentId) {
    return c.text('agent_id is required', 400);
  }
  await c.env.DB
    .prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(boss.id, agentId)
    .run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.grant', 'boss', boss.id, agentId));
  return c.json({ ok: true }, 201);
});

routes.delete('/:id/access/:agentId', async (c) => {
  const denied = requireAdmin(c);
  if (denied) return denied;
  const bossId = c.req.param('id');
  const agentId = c.req.param('agentId');
  const result = await c.env.DB
    .prepare('DELETE FROM boss_agent_access WHERE boss_id = ? AND agent_id = ?')
    .bind(bossId, agentId)
    .run();
  if (!result.meta.changes || result.meta.changes === 0) {
    return c.text('not found', 404);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.revoke', 'boss', bossId, agentId));
  return c.json({ ok: true });
});

// POST /api/bosses/:id/token — rotate a boss auth token
routes.post('/:id/token', async (c) => {
  if (getBossRole(c) !== 'admin') {
    return c.json({ error: 'admin required' }, 403);
  }
  const boss = await findBoss(c.env, c.req.param('id'));
  if (!boss) return c.text('not found', 404);
  await c.env.DB.prepare("UPDATE boss_tokens SET revoked_at = datetime('now') WHERE boss_id = ? AND revoked_at IS NULL")
    .bind(boss.id).run();
  const { token } = await issueBossToken(c.env, boss.id, 'rotated');
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', getBossId(c), 'boss.token', 'boss', boss.id));
  return c.json({ id: boss.id, name: boss.name, label: 'rotated', token });
});

export const bossesRouter = routes;

async function findBoss(env: Env, id: string): Promise<BossRow | null> {
  const exact = await env.DB.prepare('SELECT * FROM bosses WHERE id = ?').bind(id).first<BossRow>();
  if (exact) return exact;
  return env.DB.prepare("SELECT * FROM bosses WHERE id LIKE ? ESCAPE '\\' LIMIT 1").bind(`${escapeLike(id)}%`).first<BossRow>();
}
