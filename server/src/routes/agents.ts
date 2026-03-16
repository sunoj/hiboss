// Agent self-service routes for callback URL management and profile info.
// Exports GET/PUT/DELETE handlers for /api/agents/me.
// Depends on Hono, D1, and auth middleware.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/me', async (c) => {
  const agentId = getAgentId(c);
  const row = await c.env.DB
    .prepare('SELECT id, name, callback_url FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ id: string; name: string; callback_url: string | null }>();
  if (!row) {
    return c.text('agent not found', 404);
  }
  return c.json(row);
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
