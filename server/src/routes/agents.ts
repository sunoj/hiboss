// Agent self-service routes for callback URL management and profile info.
// Exports GET/PUT/DELETE handlers for /api/agents/me.
// Depends on Hono, D1, and auth middleware.

import { Hono } from 'hono';
import type { Env, Priority } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/me', async (c) => {
  const agentId = getAgentId(c);
  const row = await c.env.DB
    .prepare('SELECT id, name, callback_url, default_priority, rate_limit, last_used_at, created_at FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ id: string; name: string; callback_url: string | null; default_priority: string; rate_limit: number | null; last_used_at: string | null; created_at: string }>();
  if (!row) {
    return c.text('agent not found', 404);
  }
  return c.json(row);
});

routes.get('/', async (c) => {
  const rows = await c.env.DB
    .prepare('SELECT id, name, last_used_at, created_at FROM api_keys ORDER BY last_used_at DESC')
    .all<{ id: string; name: string; last_used_at: string | null; created_at: string }>();
  const agents = (rows.results ?? []).map((r) => ({
    ...r,
    status: agentStatus(r.last_used_at),
  }));
  return c.json({ agents });
});

routes.put('/me/config', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const validPriorities: Priority[] = ['critical', 'high', 'normal', 'low'];
  const updates: string[] = [];
  const binds: (string | number)[] = [];
  if ('default_priority' in payload) {
    const dp = payload.default_priority;
    if (typeof dp !== 'string' || !validPriorities.includes(dp as Priority)) {
      return c.text('invalid default_priority', 400);
    }
    updates.push('default_priority = ?');
    binds.push(dp);
  }
  if ('rate_limit' in payload) {
    const rl = payload.rate_limit;
    if (rl !== null && (typeof rl !== 'number' || rl < 0 || !Number.isInteger(rl))) {
      return c.text('rate_limit must be a positive integer or null', 400);
    }
    updates.push('rate_limit = ?');
    binds.push(rl as number);
  }
  if (updates.length === 0) {
    return c.text('no valid fields to update', 400);
  }
  binds.push(agentId);
  await c.env.DB
    .prepare(`UPDATE api_keys SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...binds)
    .run();
  const updated = await c.env.DB
    .prepare('SELECT default_priority, rate_limit FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ default_priority: string; rate_limit: number | null }>();
  return c.json(updated);
});

routes.put('/me/callback', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const url = typeof payload.url === 'string' ? payload.url.trim() : '';
  if (!url) {
    return c.text('url is required', 400);
  }
  await c.env.DB
    .prepare('UPDATE api_keys SET callback_url = ? WHERE id = ?')
    .bind(url, agentId)
    .run();
  return c.json({ callback_url: url });
});

routes.delete('/me/callback', async (c) => {
  const agentId = getAgentId(c);
  await c.env.DB
    .prepare('UPDATE api_keys SET callback_url = NULL WHERE id = ?')
    .bind(agentId)
    .run();
  return c.body(null, 204);
});

export const agentsRouter = routes;

function agentStatus(lastUsedAt: string | null): 'online' | 'idle' | 'offline' {
  if (!lastUsedAt) return 'offline';
  const diff = Date.now() - new Date(lastUsedAt + 'Z').getTime();
  if (diff < 5 * 60 * 1000) return 'online';   // < 5min
  if (diff < 30 * 60 * 1000) return 'idle';     // < 30min
  return 'offline';
}
