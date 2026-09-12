// Agent self-service routes for callback URL management and profile info.
// Exports GET/PUT/DELETE handlers for /api/agents/me.
// Depends on Hono, D1, and auth middleware.

import { Hono } from 'hono';
import type { Env } from '../types';
import { agentConfigUpdates } from './agent-config';
import { apiAuth, getAgentId, getAgentKeyId } from '../middleware/auth';
import { logAudit } from '../audit';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/me/bosses', async (c) => {
  const rows = await c.env.DB.prepare(
    'SELECT b.id, b.name, b.role FROM bosses b JOIN boss_agent_access ba ON ba.boss_id = b.id WHERE ba.agent_id = ? ORDER BY b.id',
  ).bind(getAgentId(c)).all<{ id: string; name: string; role: string }>();
  return c.json({ bosses: rows.results ?? [] });
});

routes.get('/me', async (c) => {
  const agentId = getAgentId(c);
  const row = await c.env.DB
    .prepare('SELECT id, name, callback_url, default_priority, rate_limit, channel_routing, avatar_url, role, session_info, last_used_at, created_at FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ id: string; name: string; callback_url: string | null; default_priority: string; rate_limit: number | null; channel_routing: string | null; avatar_url: string | null; role: string | null; session_info: string | null; last_used_at: string | null; created_at: string }>();
  if (!row) {
    return c.text('agent not found', 404);
  }
  return c.json({ ...row, agent_key_id: getAgentKeyId(c), channel_routing: row.channel_routing ? JSON.parse(row.channel_routing) : null, session_info: row.session_info ? JSON.parse(row.session_info) : null });
});

routes.get('/', async (c) => {
  const rows = await c.env.DB
    .prepare('SELECT id, name, role, session_info, last_used_at, created_at FROM api_keys ORDER BY last_used_at DESC')
    .all<{ id: string; name: string; role: string | null; session_info: string | null; last_used_at: string | null; created_at: string }>();
  const agents = (rows.results ?? []).map((r) => ({
    ...r,
    status: agentStatus(r.last_used_at),
    session_info: r.session_info ? JSON.parse(r.session_info) : null,
  }));
  return c.json({ agents });
});

routes.put('/me/config', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const parsed = agentConfigUpdates(payload);
  if (!parsed.ok) return c.text(parsed.error, 400);
  const { updates, binds } = parsed.value;
  if (updates.length === 0) {
    return c.text('no valid fields to update', 400);
  }
  binds.push(agentId);
  await c.env.DB
    .prepare(`UPDATE api_keys SET ${updates.join(', ')} WHERE id = ?`)
    .bind(...binds)
    .run();
  const updated = await c.env.DB
    .prepare('SELECT default_priority, rate_limit, channel_routing, avatar_url, role, session_info FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ default_priority: string; rate_limit: number | null; channel_routing: string | null; avatar_url: string | null; role: string | null; session_info: string | null }>();
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'agent.config', 'api_key', agentId, JSON.stringify(Object.keys(payload))));
  return c.json({ ...updated, channel_routing: updated?.channel_routing ? JSON.parse(updated.channel_routing) : null, session_info: updated?.session_info ? JSON.parse(updated.session_info) : null });
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
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'callback.set', 'api_key', agentId, url));
  return c.json({ callback_url: url });
});

routes.delete('/me/callback', async (c) => {
  const agentId = getAgentId(c);
  await c.env.DB
    .prepare('UPDATE api_keys SET callback_url = NULL WHERE id = ?')
    .bind(agentId)
    .run();
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'callback.delete', 'api_key', agentId));
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
