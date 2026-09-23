// Bootstrap route for initializing the first API key.
// Exports POST /api/bootstrap.
// Depends on Hono, hashing helpers, and Env definition.

import { Hono } from 'hono';
import type { Env } from '../types';
import { hasValidBootstrapSecret } from '../middleware/bootstrap-secret';
import { createAgent } from '../agent-keys';
import { logAudit } from '../audit';

const router = new Hono<{ Bindings: Env }>({});

router.post('/', async (c) => {
  if (!hasValidBootstrapSecret(c)) {
    return c.text('unauthorized', 401);
  }
  const name = 'default-agent';
  const inserted = await createAgent(c.env.DB, name, { type: 'system', id: 'bootstrap' }, true);
  if (!inserted) {
    return c.text('already initialized', 403);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'bootstrap', 'key.create', 'api_key', inserted.id, 'bootstrap'));
  return c.json(inserted, 201);
});

export const bootstrapRouter = router;
