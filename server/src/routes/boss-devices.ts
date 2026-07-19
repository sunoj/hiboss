// Boss device registration API for iOS APNs tokens.
// Exports bossDevicesRouter mounted at /api/boss/devices.
// Depends on boss bearer auth and D1 boss_devices storage.

import { Hono } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId } from '../middleware/auth';
import type { ApnsEnvironment } from '../apns';

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
  await c.env.DB
    .prepare(
      `INSERT INTO boss_devices (boss_id, device_token, bundle_id, environment, platform)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(device_token) DO UPDATE SET
         boss_id = excluded.boss_id,
         bundle_id = excluded.bundle_id,
         environment = excluded.environment,
         platform = excluded.platform,
         updated_at = datetime('now'),
         last_seen_at = datetime('now')`
    )
    .bind(getBossId(c), payload.token, payload.bundleId, payload.environment, payload.platform)
    .run();
  return c.json({ ok: true });
});

routes.delete('/:token', async (c) => {
  await c.env.DB
    .prepare('DELETE FROM boss_devices WHERE boss_id = ? AND device_token = ?')
    .bind(getBossId(c), c.req.param('token').toLowerCase())
    .run();
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
