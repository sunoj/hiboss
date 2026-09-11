// Boss-owned client inventory, minting, and atomic credential/push revocation.
// Exports bossClientsRouter and client contracts; depends on Hono, D1, and boss auth.
import { Hono } from 'hono';
import { bossAuth, getBossId, getClientId } from '../middleware/auth';
import { issueBossToken } from '../boss-token';
import type { Env } from '../types';
import type { BossClient, ClientId, ClientRegistration } from './types';
export type { BossClient, ClientId, ClientKind, ClientRegistration } from './types';

const MAX_LABEL_LENGTH = 100;
const routes = new Hono<{ Bindings: Env }>();
routes.use('*', bossAuth);

function registration(value: unknown): ClientRegistration | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const body = value as Record<string, unknown>;
  const { kind } = body;
  if (kind !== 'ios' && kind !== 'macos' && kind !== 'web' && kind !== 'cli') return null;
  if (typeof body.label !== 'string') return null;
  const label = body.label.trim();
  if (!label || label.length > MAX_LABEL_LENGTH || /[\x00-\x1f<>]/.test(label)) return null;
  return { kind, label };
}

async function listClients(db: D1Database, bossId: string, current: ClientId | null): Promise<BossClient[]> {
  const rows = await db.prepare(`SELECT c.id, c.kind, c.label, c.created_at, c.last_seen_at, c.revoked_at,
    EXISTS (SELECT 1 FROM boss_devices d WHERE d.client_id = c.id) AS has_push_device,
    EXISTS (SELECT 1 FROM boss_signing_keys k WHERE k.client_id = c.id) AS has_signing_key
    FROM boss_clients c WHERE c.boss_id = ? ORDER BY c.created_at DESC, c.id DESC`)
    .bind(bossId).all<Omit<BossClient, 'is_current' | 'has_push_device' | 'has_signing_key'> & {
      has_push_device: number; has_signing_key: number;
    }>();
  return rows.results.map(row => ({ ...row, has_push_device: Boolean(row.has_push_device),
    has_signing_key: Boolean(row.has_signing_key), is_current: row.id === current }));
}

routes.get('/', async c => c.json({ clients: await listClients(c.env.DB, getBossId(c), getClientId(c)) }));

routes.post('/', async c => {
  const input = registration(await c.req.json<unknown>().catch(() => null));
  if (!input) return c.json({ error: 'valid kind and label are required' }, 400);
  const grant = await issueBossToken(c.env, getBossId(c), input.label, undefined, input);
  const clients = await listClients(c.env.DB, getBossId(c), getClientId(c));
  return c.json({ client: clients.find(client => client.id === grant.clientId), token: grant.token }, 201);
});

routes.delete('/:id', async c => {
  const id = c.req.param('id');
  if (id === getClientId(c)) return c.json({ error: 'use token self-revoke for this client' }, 403);
  const bossId = getBossId(c);
  const owned = await c.env.DB.prepare('SELECT id FROM boss_clients WHERE id = ? AND boss_id = ?')
    .bind(id, bossId).first();
  if (!owned) return c.json({ error: 'client not found' }, 404);
  await c.env.DB.batch([
    c.env.DB.prepare("UPDATE boss_clients SET revoked_at = COALESCE(revoked_at, datetime('now')) WHERE id = ? AND boss_id = ?").bind(id, bossId),
    c.env.DB.prepare("UPDATE boss_tokens SET revoked_at = COALESCE(revoked_at, datetime('now')) WHERE client_id = ?").bind(id),
    c.env.DB.prepare("UPDATE boss_signing_keys SET revoked_at = COALESCE(revoked_at, datetime('now')) WHERE client_id = ?").bind(id),
    c.env.DB.prepare('DELETE FROM boss_devices WHERE client_id = ?').bind(id),
    c.env.DB.prepare("INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id) VALUES ('boss', ?, 'client.revoke', 'client', ?)").bind(bossId, id),
  ]);
  return c.json({ ok: true });
});

export const bossClientsRouter = routes;
