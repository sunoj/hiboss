// Boss-owned destination inventory and mutations, plus admin provider management.
// Exports two routers; depends on boss auth, strict request parsers, and D1 ownership predicates.
import { Hono } from 'hono';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import type { Env } from '../types';
import { probeDestination, type ProbeDestination } from '../delivery/probe';
import { destinationsMode, parseDestination, parseDestinationPatch, parseProvider } from '../delivery';
import { credentialHash, effectiveCredential } from '../delivery/targets';

const destinations = new Hono<{ Bindings: Env }>();
const providers = new Hono<{ Bindings: Env }>();
destinations.use('*', bossAuth);
providers.use('*', bossAuth);
destinations.use('*', async (c, next) => {
  if (c.req.method !== 'GET' && getBossRole(c) === 'viewer') return c.json({ error: 'viewer is read-only' }, 403);
  await next();
});
providers.use('*', async (c, next) => {
  if (getBossRole(c) !== 'admin') return c.json({ error: 'admin required' }, 403);
  await next();
});

destinations.get('/', async c => {
  const rows = await c.env.DB.prepare(`SELECT d.*, p.label AS provider_label,
    (SELECT COUNT(*) FROM destination_routes r WHERE r.destination_id = d.id) AS route_count
    FROM boss_destinations d LEFT JOIN channel_providers p ON p.id = d.provider_id
    WHERE d.boss_id = ? ORDER BY d.created_at, d.id`).bind(getBossId(c)).all();
  const providers = await c.env.DB.prepare('SELECT id, provider, label, created_at FROM channel_providers ORDER BY created_at, id').all();
  return c.json({ destinations: rows.results, providers: providers.results, mode: destinationsMode(c.env.DESTINATIONS_MODE) });
});

destinations.patch('/:id', async c => {
  const input = parseDestinationPatch(await c.req.json<unknown>().catch(() => null));
  if (!input) return c.json({ error: 'invalid destination patch' }, 400);
  const entries = Object.entries(input);
  const row = await c.env.DB.prepare(`UPDATE boss_destinations SET ${entries.map(([key]) => `${key} = ?`).join(', ')}
    WHERE id = ? AND boss_id = ? RETURNING *`)
    .bind(...entries.map(([, value]) => typeof value === 'boolean' ? Number(value) : value), c.req.param('id'), getBossId(c)).first();
  return row ? c.json({ destination: row }) : c.json({ error: 'destination not found' }, 404);
});

destinations.post('/', async c => {
  const input = parseDestination(await c.req.json<unknown>().catch(() => null));
  if (!input) return c.json({ error: 'invalid destination' }, 400);
  const provider = input.kind === 'telegram_chat' ? 'telegram' : 'discord';
  const row = await c.env.DB.prepare(`INSERT INTO boss_destinations (boss_id, kind, provider_id, target, label)
    SELECT ?, ?, id, ?, ? FROM channel_providers WHERE id = ? AND provider = ? RETURNING *`)
    .bind(getBossId(c), input.kind, JSON.stringify(input.target), input.label, input.provider_id, provider).first();
  return row ? c.json({ destination: row }, 201) : c.json({ error: 'matching provider required' }, 400);
});

destinations.delete('/:id', async c => {
  const row = await c.env.DB.prepare('DELETE FROM boss_destinations WHERE id = ? AND boss_id = ? RETURNING id')
    .bind(c.req.param('id'), getBossId(c)).first();
  return row ? c.json({ ok: true }) : c.json({ error: 'destination not found' }, 404);
});

destinations.post('/:id/test', async c => {
  const row = await c.env.DB.prepare(`SELECT d.*, p.credentials FROM boss_destinations d
    LEFT JOIN channel_providers p ON p.id = d.provider_id WHERE d.id = ? AND d.boss_id = ?`)
    .bind(c.req.param('id'), getBossId(c)).first<ProbeDestination>();
  if (!row) return c.json({ error: 'destination not found' }, 404);
  if (destinationsMode(c.env.DESTINATIONS_MODE) !== 'on') return c.json({ error: 'destination probes require on mode' }, 409);
  if (row.kind === 'native_live') return c.json({ error: 'native streams do not support probes' }, 409);
  try {
    const external_message_id = await probeDestination(c.env, row);
    return c.json({ ok: true, external_message_id });
  } catch { return c.json({ error: 'destination probe failed' }, 502); }
});

providers.get('/', async c => {
  const rows = await c.env.DB.prepare('SELECT id, provider, label, created_at FROM channel_providers ORDER BY created_at, id').all();
  return c.json({ providers: rows.results });
});

providers.post('/', async c => {
  const input = parseProvider(await c.req.json<unknown>().catch(() => null));
  if (!input) return c.json({ error: 'invalid provider' }, 400);
  const hash = await credentialHash(effectiveCredential(input.credentials));
  const row = await c.env.DB.prepare(`INSERT INTO channel_providers (provider, label, credentials, credential_hash) VALUES (?, ?, ?, ?)
    ON CONFLICT DO NOTHING RETURNING id, provider, label, created_at`)
    .bind(input.provider, input.label, JSON.stringify(input.credentials), hash).first();
  return row ? c.json({ provider: row }, 201) : c.json({ error: 'provider credentials already registered' }, 409);
});

export const bossDestinationsRouter = destinations;
export const bossProvidersRouter = providers;
