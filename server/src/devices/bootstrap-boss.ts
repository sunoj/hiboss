// First-boss bootstrap: creates the admin boss of an empty server plus a pairing code.
// Exports bootstrapBossRouter (POST /api/bootstrap/boss); no bearer token is ever returned.
// Depends on the configured BOOTSTRAP_SECRET and the pairing-code primitives.
import { Hono } from 'hono';
import type { Env } from '../types';
import { logAudit } from '../audit';
import { hashApiKey } from '../middleware/auth';
import { hasValidBootstrapSecret } from '../middleware/bootstrap-secret';
import { newPairingCode, PAIRING_CODE_TTL_MS } from '../routes/pairing';

const NAME_PATTERN = /^[^<>&\u0000-\u001f]{1,64}$/;
const router = new Hono<{ Bindings: Env }>({});

router.post('/boss', async (c) => {
  // Unlike agent bootstrap, an unset secret refuses: the first boss is the server's admin.
  if (!c.env.BOOTSTRAP_SECRET) return c.json({ error: 'set BOOTSTRAP_SECRET on the server to bootstrap a boss' }, 403);
  if (!hasValidBootstrapSecret(c)) return c.json({ error: 'bootstrap secret required' }, 401);
  const body = await c.req.json<{ name?: unknown }>().catch(() => ({ name: undefined }));
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (!NAME_PATTERN.test(name)) return c.json({ error: 'name must be 1-64 printable characters' }, 400);
  const bossId = crypto.randomUUID().replaceAll('-', '');
  const code = newPairingCode();
  const expiresAt = new Date(Date.now() + PAIRING_CODE_TTL_MS).toISOString();
  const [created] = await c.env.DB.batch([
    c.env.DB.prepare("INSERT INTO bosses (id, name, role) SELECT ?, ?, 'admin' WHERE NOT EXISTS (SELECT 1 FROM bosses)")
      .bind(bossId, name),
    c.env.DB.prepare('INSERT INTO boss_pairing_codes (boss_id, code_hash, expires_at) SELECT id, ?, ? FROM bosses WHERE id = ?')
      .bind(await hashApiKey(code), expiresAt, bossId),
  ]);
  if (!created.meta.changes) return c.json({ error: 'a boss already exists; pair from an existing boss device' }, 409);
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'bootstrap', 'boss.create', 'boss', bossId, JSON.stringify({ name, role: 'admin' })));
  return c.json({ boss: { id: bossId, name, role: 'admin' }, code, expires_at: expiresAt }, 201);
});

export const bootstrapBossRouter = router;
