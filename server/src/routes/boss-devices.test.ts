// Integration tests for boss iOS device registration endpoints.
// Covers boss bearer auth, token upsert, and deletion.
// Depends on cloudflare:test, test helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { seedDatabase } from '../test-helpers';

const BOSS_TOKEN = 'hb_boss_devices_00112233445566778899';
const DEVICE_TOKEN = 'abcdef1234567890';
let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  const tokenHash = await hashApiKey(BOSS_TOKEN);
  await env.DB
    .prepare('INSERT OR REPLACE INTO bosses (id, name, role, token_hash) VALUES (?, ?, ?, ?)')
    .bind('boss-devices-test', 'Device Boss', 'admin', tokenHash)
    .run();
  bossId = 'boss-devices-test';
});

function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' };
}

describe('POST /api/boss/devices', () => {
  it('upserts an iOS APNs device for the authenticated boss', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/devices', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({
        token: DEVICE_TOKEN.toUpperCase(),
        bundleId: 'com.hiboss.ios',
        environment: 'sandbox',
        platform: 'ios',
      }),
    });

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    const row = await env.DB
      .prepare('SELECT boss_id, device_token, bundle_id, environment, platform FROM boss_devices WHERE device_token = ?')
      .bind(DEVICE_TOKEN)
      .first<{ boss_id: string; device_token: string; bundle_id: string; environment: string; platform: string }>();
    expect(row).toEqual({
      boss_id: bossId,
      device_token: DEVICE_TOKEN,
      bundle_id: 'com.hiboss.ios',
      environment: 'sandbox',
      platform: 'ios',
    });
  });

  it('updates bundle and environment when the same token registers again', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/devices', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({
        token: DEVICE_TOKEN,
        bundleId: 'com.hiboss.ios.beta',
        environment: 'production',
        platform: 'ios',
      }),
    });

    expect(res.status).toBe(200);
    const row = await env.DB
      .prepare('SELECT COUNT(*) AS count, bundle_id, environment FROM boss_devices WHERE device_token = ?')
      .bind(DEVICE_TOKEN)
      .first<{ count: number; bundle_id: string; environment: string }>();
    expect(row?.count).toBe(1);
    expect(row?.bundle_id).toBe('com.hiboss.ios.beta');
    expect(row?.environment).toBe('production');
  });

  it('rejects invalid registrations', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/devices', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ token: 'not-hex', bundleId: '', environment: 'dev', platform: 'web' }),
    });

    expect(res.status).toBe(400);
  });
});

describe('DELETE /api/boss/devices/:token', () => {
  it('deletes the authenticated boss device token', async () => {
    const res = await SELF.fetch(`http://localhost/api/boss/devices/${DEVICE_TOKEN}`, {
      method: 'DELETE',
      headers: bossHeaders(),
    });

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
    const row = await env.DB
      .prepare('SELECT id FROM boss_devices WHERE device_token = ?')
      .bind(DEVICE_TOKEN)
      .first<{ id: string }>();
    expect(row).toBeNull();
  });
});
