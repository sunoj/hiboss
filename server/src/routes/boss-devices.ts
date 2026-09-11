// Boss device registration API for iOS APNs tokens.
// Exports bossDevicesRouter mounted at /api/boss/devices.
// Depends on boss bearer auth and D1 boss_devices/audit_log storage.

import { Hono } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId, getClientId } from '../middleware/auth';
import type { ApnsEnvironment } from '../apns';
import { deleteBossDevice } from '../push/devices';

type BossDevicePlatform = 'ios';

interface BossDeviceRequest {
  token: string;
  bundleId: string;
  environment: ApnsEnvironment;
  platform: BossDevicePlatform;
}

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);

routes.post('/', async (c) => {
  const body = await c.req.json<unknown>();
  const payload = parseBossDeviceRequest(body);
  if (!payload) {
    return c.text('invalid device registration', 400);
  }
  const bossId = getBossId(c);
  // Capture the prior owner and move the row atomically, including concurrent registrations.
  const audit = c.env.DB.prepare(
    `INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
     SELECT 'boss', ?, 'device.reparent', 'device', id, json_object('old_boss_id', boss_id)
     FROM boss_devices WHERE device_token = ? AND boss_id != ?`
  ).bind(bossId, payload.token, bossId);
  const upsert = c.env.DB
    .prepare(
      `INSERT INTO boss_devices (boss_id, device_token, bundle_id, environment, platform, client_id)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(device_token) DO UPDATE SET
         boss_id = excluded.boss_id,
         client_id = excluded.client_id,
         bundle_id = excluded.bundle_id,
         environment = excluded.environment,
         platform = excluded.platform,
         updated_at = datetime('now'),
         last_seen_at = datetime('now')`
    )
    .bind(bossId, payload.token, payload.bundleId, payload.environment, payload.platform, getClientId(c));
  const [auditResult] = await c.env.DB.batch([audit, upsert]);
  return c.json({ ok: true, ...(auditResult.meta.changes > 0 ? { reparented: true } : {}) });
});

routes.delete('/:token', async (c) => {
  await deleteBossDevice(c.env, getBossId(c), c.req.param('token').toLowerCase());
  return c.json({ ok: true });
});

function parseBossDeviceRequest(value: unknown): BossDeviceRequest | null {
  if (!value || typeof value !== 'object') return null;
  const record = value as Record<string, unknown>;
  const token = typeof record.token === 'string' ? record.token.trim() : '';
  const bundleId = typeof record.bundleId === 'string' ? record.bundleId.trim() : '';
  const environment = record.environment;
  const platform = record.platform;
  if (!/^[0-9a-fA-F]+$/.test(token) || token.length === 0 || token.length % 2 !== 0) return null;
  if (!bundleId) return null;
  if (environment !== 'sandbox' && environment !== 'production') return null;
  if (platform !== 'ios') return null;
  return { token: token.toLowerCase(), bundleId, environment, platform };
}

export const bossDevicesRouter = routes;
