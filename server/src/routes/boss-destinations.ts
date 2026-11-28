// Boss-owned destination inventory and mutations.
// Exports the destination router; depends on boss auth, strict request parsers, and D1 ownership predicates.
import { Hono } from 'hono';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import type { Env } from '../types';
import { probeDestination, type ProbeDestination } from '../delivery/probe';
import { destinationsMode, parseDestinationPatch } from '../delivery';
import { inFlightDeliveryGuard, isDeliveryInProgressError, preserveMergedDeliveries } from '../delivery/delete-destination';

const destinations = new Hono<{ Bindings: Env }>();
destinations.use('*', bossAuth);
destinations.use('*', async (c, next) => {
  if (c.req.method !== 'GET' && getBossRole(c) === 'viewer') return c.json({ error: 'viewer is read-only' }, 403);
  await next();
});
destinations.get('/', async c => {
  const rows = await c.env.DB.prepare('SELECT * FROM boss_destinations WHERE boss_id = ? ORDER BY created_at, id')
    .bind(getBossId(c)).all();
  return c.json({ destinations: rows.results, mode: destinationsMode(c.env.DESTINATIONS_MODE) });
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

destinations.delete('/:id', async c => {
  const id = c.req.param('id');
  const owned = await c.env.DB.prepare('SELECT id FROM boss_destinations WHERE id = ? AND boss_id = ?')
    .bind(id, getBossId(c)).first<{ id: string }>();
  if (!owned) return c.json({ error: 'destination not found' }, 404);
  const statements = await preserveMergedDeliveries(c.env, id);
  statements.unshift(inFlightDeliveryGuard(c.env, [id]));
  statements.push(c.env.DB.prepare('DELETE FROM boss_destinations WHERE id = ? AND boss_id = ?').bind(id, getBossId(c)));
  try { await c.env.DB.batch(statements); }
  catch (error) {
    if (isDeliveryInProgressError(error)) return c.json({ error: 'delivery in progress, retry' }, 409);
    throw error;
  }
  return c.json({ ok: true });
});

destinations.post('/:id/test', async c => {
  const row = await c.env.DB.prepare('SELECT * FROM boss_destinations WHERE id = ? AND boss_id = ?')
    .bind(c.req.param('id'), getBossId(c)).first<ProbeDestination>();
  if (!row) return c.json({ error: 'destination not found' }, 404);
  if (destinationsMode(c.env.DESTINATIONS_MODE) !== 'on') return c.json({ error: 'destination probes require on mode' }, 409);
  if (row.kind === 'native_live') return c.json({ error: 'native streams do not support probes' }, 409);
  try {
    const external_message_id = await probeDestination(c.env, row);
    return c.json({ ok: true, external_message_id });
  } catch { return c.json({ error: 'destination probe failed' }, 502); }
});

export const bossDestinationsRouter = destinations;
