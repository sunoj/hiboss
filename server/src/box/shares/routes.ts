// Authenticated creation, listing and revocation of public Box capabilities.
// Uses scoped item reads and stores only SHA-256 token hashes in D1.
import { Hono } from 'hono';
import type { Env } from '../../types';
import { getAgentId, getBossId, isBossAuth } from '../../middleware/auth';
import { boxBossIds, canEditItem } from '../access';
import { findItem } from '../store';

export async function tokenHash(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}

interface ShareRow {
  id: string;
  item_id: string;
  created_at: string;
  expires_at: string;
  revoked_at: string | null;
  created_by_agent: string | null;
  agent_name: string | null;
  view_count: number;
  last_viewed_at: string | null;
}

export const shareRoutes = new Hono<{ Bindings: Env }>();

shareRoutes.post('/items/:id/shares', async c => {
  const item = await findItem(c, c.req.param('id'));
  if (!item || !canEditItem(c, item)) return c.text('not found', 404);
  const body: unknown = await c.req.json().catch(() => null);
  if (!body || typeof body !== 'object' || Array.isArray(body)) return c.text('invalid body', 400);
  const supplied = (body as { ttlSeconds?: unknown }).ttlSeconds;
  const ttl = supplied === undefined ? 604800 : supplied;
  if (typeof ttl !== 'number' || !Number.isFinite(ttl) || ttl < 3600 || ttl > 2592000) {
    return c.text('invalid ttlSeconds', 400);
  }
  const token = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32))))
    .replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  const id = `bs_${crypto.randomUUID().replaceAll('-', '')}`;
  const createdAt = new Date().toISOString();
  const expiresAt = new Date(Date.parse(createdAt) + ttl * 1000).toISOString();
  await c.env.DB.prepare(`INSERT INTO box_shares
    (id, item_id, boss_id, token_hash, created_by_agent, created_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)`).bind(id, item.id, item.boss_id, await tokenHash(token),
    isBossAuth(c) ? null : getAgentId(c), createdAt, expiresAt).run();
  return c.json({ id, itemId: item.id, url: `${new URL(c.req.url).origin}/s/${token}`,
    expiresAt, createdAt }, 201);
});

shareRoutes.get('/items/:id/shares', async c => {
  const item = await findItem(c, c.req.param('id'));
  if (!item || !canEditItem(c, item)) return c.text('not found', 404);
  const rows = await c.env.DB.prepare(`SELECT s.*, a.name AS agent_name FROM box_shares s
    LEFT JOIN api_keys a ON a.id = s.created_by_agent WHERE s.item_id = ? AND s.boss_id = ?
    ORDER BY s.created_at DESC, s.id`).bind(item.id, item.boss_id).all<ShareRow>();
  const now = new Date().toISOString();
  return c.json({ shares: rows.results.map(row => ({ id: row.id, itemId: row.item_id,
    createdAt: row.created_at, expiresAt: row.expires_at, revokedAt: row.revoked_at,
    createdBy: row.created_by_agent === null ? 'boss' : row.agent_name ?? row.created_by_agent,
    viewCount: row.view_count, lastViewedAt: row.last_viewed_at,
    active: row.revoked_at === null && row.expires_at > now })) });
});

shareRoutes.delete('/shares/:shareId', async c => {
  const bosses = await boxBossIds(c);
  if (!bosses.length) return c.text('not found', 404);
  const owner = isBossAuth(c) ? 'boss_id = ?' : 'created_by_agent = ?';
  const result = await c.env.DB.prepare(`UPDATE box_shares SET revoked_at = COALESCE(revoked_at, ?)
    WHERE id = ? AND boss_id IN (${bosses.map(() => '?').join(',')}) AND ${owner}`)
    .bind(new Date().toISOString(), c.req.param('shareId'), ...bosses,
      isBossAuth(c) ? getBossId(c) : getAgentId(c)).run();
  return result.meta.changes ? c.body(null, 204) : c.text('not found', 404);
});
