// Agent self-service routes for callback URL management and profile info.
// Exports GET/PUT/DELETE handlers for /api/agents/me.
// Depends on Hono, D1, and auth middleware.

import { Hono } from 'hono';
import type { Channel, Env, Priority } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { logAudit } from '../audit';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/me', async (c) => {
  const agentId = getAgentId(c);
  const row = await c.env.DB
    .prepare('SELECT id, name, callback_url, default_priority, rate_limit, channel_routing, avatar_url, role, session_info, last_used_at, created_at FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ id: string; name: string; callback_url: string | null; default_priority: string; rate_limit: number | null; channel_routing: string | null; avatar_url: string | null; role: string | null; session_info: string | null; last_used_at: string | null; created_at: string }>();
  if (!row) {
    return c.text('agent not found', 404);
  }
  return c.json({ ...row, channel_routing: row.channel_routing ? JSON.parse(row.channel_routing) : null, session_info: row.session_info ? JSON.parse(row.session_info) : null });
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
  if ('channel_routing' in payload) {
    const cr = payload.channel_routing;
    if (cr === null) {
      updates.push('channel_routing = NULL');
    } else if (typeof cr === 'object' && !Array.isArray(cr)) {
      const validChannels: Channel[] = ['discord', 'telegram', 'email'];
      for (const [, ch] of Object.entries(cr as Record<string, unknown>)) {
        if (typeof ch !== 'string' || !validChannels.includes(ch as Channel)) {
          return c.text('channel_routing values must be valid channels', 400);
        }
      }
      updates.push('channel_routing = ?');
      binds.push(JSON.stringify(cr));
    } else {
      return c.text('channel_routing must be an object or null', 400);
    }
  }
  if ('avatar_url' in payload) {
    const av = payload.avatar_url;
    if (av === null) {
      updates.push('avatar_url = NULL');
    } else if (typeof av === 'string') {
      updates.push('avatar_url = ?');
      binds.push(av);
    } else {
      return c.text('avatar_url must be a string or null', 400);
    }
  }
  if ('role' in payload) {
    const role = payload.role;
    const validRoles = ['orchestrator', 'worker', 'reviewer'];
    if (role === null) {
      updates.push('role = NULL');
    } else if (typeof role === 'string' && validRoles.includes(role)) {
      updates.push('role = ?');
      binds.push(role);
    } else {
      return c.text('role must be orchestrator, worker, or reviewer', 400);
    }
  }
  if ('session_info' in payload) {
    const si = payload.session_info;
    if (si === null) {
      updates.push('session_info = NULL');
    } else if (typeof si === 'object' && !Array.isArray(si)) {
      updates.push('session_info = ?');
      binds.push(JSON.stringify(si));
    } else {
      return c.text('session_info must be an object or null', 400);
    }
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
