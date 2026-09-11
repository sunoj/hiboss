// Integration tests for boss iOS device registration endpoints.
// Covers boss bearer auth, token upsert, and deletion.
// Depends on cloudflare:test, test helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';

const BOSS_TOKEN = 'hb_boss_devices_00112233445566778899';
const DEVICE_TOKEN = 'abcdef1234567890';
let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  bossId = await seedBossToken('Device Boss', 'admin', BOSS_TOKEN, 'boss-devices-test');
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
});

describe('POST /api/boss/devices updates and validation', () => {
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

describe('POST /api/boss/devices ownership', () => {
  it('audits a re-parent once and immediately removes the token from the old boss fan-out', async () => {
    const token = 'abcdef9876543210';
    const newBossToken = 'hb_boss_devices_new_owner';
    const newBossId = await seedBossToken('New Device Boss', 'manager', newBossToken);
    const register = (bearer: string) => SELF.fetch('http://localhost/api/boss/devices', {
      method: 'POST',
      headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ token, bundleId: 'com.hiboss.ios', environment: 'sandbox', platform: 'ios' }),
    });
    const initial = await register(BOSS_TOKEN);
    expect(initial.status).toBe(200);
    expect(await initial.json()).toEqual({ ok: true });
    const device = await env.DB.prepare('SELECT id FROM boss_devices WHERE device_token = ?')
      .bind(token).first<{ id: string }>();
    const moved = await register(newBossToken);
    expect(moved.status).toBe(200);
    expect(await moved.json()).toEqual({ ok: true, reparented: true });
    // Same boss_id filter used by notifyBossDevices for push destination selection.
    const oldFanout = await env.DB.prepare('SELECT device_token FROM boss_devices WHERE boss_id IN (?)')
      .bind(bossId).all<{ device_token: string }>();
    expect(oldFanout.results.map((row) => row.device_token)).not.toContain(token);
    const newFanout = await env.DB.prepare('SELECT device_token FROM boss_devices WHERE boss_id IN (?)')
      .bind(newBossId).all<{ device_token: string }>();
    expect(newFanout.results).toEqual([{ device_token: token }]);
    const repeated = await register(newBossToken);
    expect(repeated.status).toBe(200);
    expect(await repeated.json()).toEqual({ ok: true });
    const audits = await env.DB.prepare(
      "SELECT actor_type, actor_id, resource_type, resource_id, details FROM audit_log WHERE action = 'device.reparent'"
    ).all();
    expect(audits.results).toEqual([{
      actor_type: 'boss', actor_id: newBossId, resource_type: 'device', resource_id: device?.id,
      details: JSON.stringify({ old_boss_id: bossId }),
    }]);
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
