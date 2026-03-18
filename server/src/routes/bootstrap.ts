// Bootstrap route for initializing the first API key.
// Exports POST /api/bootstrap.
// Depends on Hono, hashing helpers, and Env definition.

import { Context, Hono } from 'hono';
import type { Env } from '../types';
import { hashApiKey } from '../middleware/auth';
import { logAudit } from '../audit';

const router = new Hono<{ Bindings: Env }>({});

router.post('/', async (c) => {
  if (!hasValidBootstrapSecret(c)) {
    return c.text('unauthorized', 401);
  }
  const name = 'default-agent';
  const key = `hb_${generateHex(16)}`;
  const keyHash = await hashApiKey(key);
  const inserted = await c.env.DB
    .prepare('INSERT INTO api_keys (name, key_hash) SELECT ?, ? WHERE NOT EXISTS (SELECT 1 FROM api_keys) RETURNING id, name')
    .bind(name, keyHash)
    .first<{ id: string; name: string }>();
  if (!inserted) {
    return c.text('already initialized', 403);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'bootstrap', 'key.create', 'api_key', inserted.id, 'bootstrap'));
  return c.json({ id: inserted.id, name: inserted.name, key }, 201);
});

export const bootstrapRouter = router;

function generateHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}

function hasValidBootstrapSecret(c: Context<{ Bindings: Env }>): boolean {
  const expectedSecret = c.env.BOOTSTRAP_SECRET;
  if (!expectedSecret) {
    return true;
  }
  const headerSecret = c.req.header('X-Bootstrap-Secret');
  if (headerSecret === expectedSecret) {
    return true;
  }
  const authorization = c.req.header('Authorization');
  const bearerPrefix = 'Bearer ';
  return authorization?.startsWith(bearerPrefix) ? authorization.slice(bearerPrefix.length) === expectedSecret : false;
}
