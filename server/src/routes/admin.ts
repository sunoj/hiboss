// Admin routes for creating API keys.
// Exports POST /api/keys.
// Depends on Hono, auth middleware, hashing helpers, and shared types.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { agentAdmin } from '../middleware/agent-admin';
import { createAgent } from '../agent-keys';
import { logAudit } from '../audit';

const router = new Hono<{ Bindings: Env }>({});
router.use('*', apiAuth);
router.use('*', agentAdmin);

router.post('/keys', async (c) => {
  const payload = await c.req.json<Record<string, unknown>>();
  const name = typeof payload.name === 'string' ? payload.name.trim() : '';
  if (!name) {
    return c.text('name is required', 400);
  }
  const inserted = await createAgent(c.env.DB, name, { type: 'agent', id: getAgentId(c) });
  if (!inserted) {
    return c.text('agent name already exists', 409);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', getAgentId(c), 'key.create', 'api_key', inserted.id, name));
  return c.json(inserted, 201);
});

router.get('/keys', async (c) => {
  const rows = await c.env.DB
    .prepare('SELECT id, name, created_at, last_used_at FROM api_keys ORDER BY created_at DESC')
    .all<{ id: string; name: string; created_at: string; last_used_at: string | null }>();
  return c.json({
    keys: rows.results ?? [],
  });
});

export const adminRouter = router;
