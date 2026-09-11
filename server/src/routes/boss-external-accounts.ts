// Own external identity CRUD and admin management under the existing bosses surface.
// Exports routers and legacy-write helpers; depends on boss auth and atomic D1 batches.
import { Hono, type MiddlewareHandler } from 'hono';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import type { Env } from '../types';
type Provider = 'telegram' | 'discord';
interface Account { id: string; boss_id: string; provider: Provider; provider_user_id: string; created_at: string }
const columns = { telegram: 'telegram_user_id', discord: 'discord_user_id' } as const;

export async function identityConflict(env: Env, bossId: string, provider: Provider, userId: string): Promise<boolean> {
  const found = await env.DB.prepare(`SELECT 1 FROM boss_external_accounts WHERE provider = ? AND provider_user_id = ? AND boss_id != ?
    UNION ALL SELECT 1 FROM bosses WHERE ${columns[provider]} = ? AND id != ? LIMIT 1`)
    .bind(provider, userId, bossId, userId, bossId).first();
  return Boolean(found);
}
export function legacyIdentityWrites(env: Env, bossId: string, provider: Provider, previous: string | null, next: string | null): D1PreparedStatement[] {
  const writes = [env.DB.prepare('DELETE FROM boss_external_accounts WHERE boss_id = ? AND provider = ? AND provider_user_id = ?')
    .bind(bossId, provider, previous)];
  if (next) writes.push(env.DB.prepare(`INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id)
    SELECT ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM boss_external_accounts WHERE boss_id = ? AND provider = ? AND provider_user_id = ?)`)
    .bind(bossId, provider, next, bossId, provider, next));
  return writes;
}
function accountRouter(admin: boolean): Hono<{ Bindings: Env }> {
  const router = new Hono<{ Bindings: Env }>();
  router.use('*', bossAuth);
  const base = admin ? '/:bossId/external-accounts' : '/';
  const authorize: MiddlewareHandler<{ Bindings: Env }> = async (c, next) => {
    if (admin && getBossRole(c) !== 'admin') return c.json({ error: 'admin required' }, 403);
    if (c.req.method !== 'GET' && getBossRole(c) === 'viewer') return c.json({ error: 'viewer is read-only' }, 403);
    const bossId = admin ? c.req.param('bossId') : getBossId(c);
    if (!bossId) return next();
    if (!await c.env.DB.prepare('SELECT id FROM bosses WHERE id = ?').bind(bossId).first()) return c.json({ error: 'boss not found' }, 404);
    await next();
  };
  router.use(base, authorize);
  router.use(`${base === '/' ? '' : base}/*`, authorize);
  router.get(base, async c => {
    const rows = await c.env.DB.prepare('SELECT * FROM boss_external_accounts WHERE boss_id = ? ORDER BY created_at, id')
      .bind(admin ? c.req.param('bossId') : getBossId(c)).all<Account>();
    return c.json({ external_accounts: rows.results });
  });
  router.post(base, async c => {
    const body = await c.req.json<Record<string, unknown>>().catch(() => null);
    if (!body || Object.keys(body).some(key => !['provider', 'provider_user_id'].includes(key))
      || (body.provider !== 'telegram' && body.provider !== 'discord')
      || typeof body.provider_user_id !== 'string' || !/^\d{1,30}$/.test(body.provider_user_id)) return c.json({ error: 'invalid external account' }, 400);
    const bossId = admin ? c.req.param('bossId') : getBossId(c);
    if (await identityConflict(c.env, bossId, body.provider, body.provider_user_id)) return c.json({ error: 'external account already linked' }, 409);
    const row = await c.env.DB.prepare(`INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id)
      VALUES (?, ?, ?) ON CONFLICT(provider, provider_user_id) DO NOTHING RETURNING *`)
      .bind(bossId, body.provider, body.provider_user_id).first<Account>();
    return row ? c.json({ external_account: row }, 201) : c.json({ error: 'external account already linked' }, 409);
  });
  router.delete(`${base === '/' ? '' : base}/:id`, async c => {
    const bossId = admin ? c.req.param('bossId') : getBossId(c);
    const row = await c.env.DB.prepare('SELECT * FROM boss_external_accounts WHERE id = ? AND boss_id = ?')
      .bind(c.req.param('id'), bossId).first<Account>();
    if (!row) return c.json({ error: 'external account not found' }, 404);
    await c.env.DB.batch([
      c.env.DB.prepare(`UPDATE bosses SET ${columns[row.provider]} = NULL WHERE id = ? AND ${columns[row.provider]} = ?`).bind(bossId, row.provider_user_id),
      c.env.DB.prepare('DELETE FROM boss_external_accounts WHERE id = ? AND boss_id = ?').bind(row.id, bossId),
    ]);
    return c.json({ ok: true });
  });
  return router;
}
export const bossExternalAccountsRouter = accountRouter(false);
export const adminExternalAccountsRouter = accountRouter(true);
