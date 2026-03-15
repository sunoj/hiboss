// Bootstrap route for initializing the first API key.
// Exports POST /api/bootstrap.
// Depends on Hono, hashing helpers, and Env definition.

import { Hono } from 'hono';
import type { Env } from '../types';
import { hashApiKey } from '../middleware/auth';

const router = new Hono<{ Bindings: Env }>({});

router.post('/', async (c) => {
  const countRow = await c.env.DB
    .prepare('SELECT COUNT(*) AS count FROM api_keys')
    .first<{ count: number }>();
  const count = countRow?.count ?? 0;
  if (count > 0) {
    return c.text('already initialized', 403);
  }
  const name = 'default-agent';
  const key = `hb_${generateHex(16)}`;
  const keyHash = await hashApiKey(key);
  const inserted = await c.env.DB
    .prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id, name')
    .bind(name, keyHash)
    .first<{ id: string; name: string }>();
  if (!inserted) {
    return c.text('failed to create key', 500);
  }
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
