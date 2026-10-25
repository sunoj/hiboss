// Lists and revokes bearer tokens belonging to the authenticated boss.
// Exports bossTokensRouter mounted at /api/boss/tokens.
// Depends on boss auth and the revocation cascade; hashes are never returned.

import { Hono } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId, getBossRole, getBossTokenId } from '../middleware/auth';
import { revokeBossTokens } from '../boss-clients/revoke';

interface BossTokenRow {
  id: string;
  label: string;
  created_at: string;
  last_used_at: string | null;
  revoked_at: string | null;
}

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);

routes.get('/', async (c) => {
  if (getBossRole(c) !== 'admin') return c.json({ error: 'admin required' }, 403);
  const rows = await c.env.DB.prepare(
    'SELECT id, label, created_at, last_used_at, revoked_at FROM boss_tokens WHERE boss_id = ? ORDER BY created_at DESC',
  ).bind(getBossId(c)).all<BossTokenRow>();
  return c.json({ tokens: rows.results ?? [] });
});

routes.post('/revoke-others', async (c) => {
  if (getBossRole(c) !== 'admin') return c.json({ error: 'admin required' }, 403);
  const revoked = await revokeBossTokens(c.env.DB, { sql: 't.boss_id = ? AND t.id != ?', binds: [getBossId(c), getBossTokenId(c)] });
  return c.json({ revoked });
});

routes.delete('/:tokenId', async (c) => {
  const tokenId = c.req.param('tokenId');
  const isSelf = tokenId === getBossTokenId(c);
  if (!isSelf && getBossRole(c) !== 'admin') return c.json({ error: 'admin required' }, 403);
  const revoked = await revokeBossTokens(c.env.DB, { sql: 't.boss_id = ? AND t.id = ?', binds: [getBossId(c), tokenId] });
  if (!revoked) return c.text('token not found', 404);
  return isSelf ? c.json({ ok: true, authenticated: false }) : c.json({ ok: true });
});

export const bossTokensRouter = routes;
