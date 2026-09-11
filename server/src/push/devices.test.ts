// Verifies device deletion/pruning removes APNs inventory through API and delivery paths.
// Depends on real D1, boss authentication, notification delivery, and mocked APNs sends.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, expect, it, vi } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { notifyBossAgents } from '../notify';
import { resolveDestinations } from '../delivery/destinations';
import { sendDestination } from '../delivery/adapters';
import * as apns from '../apns';
import type { MessageRow } from '../types';

const bossId = 'cleanup-boss';
const bossToken = 'cleanup-boss-token';
const deviceToken = 'abcdef1234';
beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Cleanup Boss', 'admin', bossToken, bossId);
  await seedBossToken('Other Boss', 'admin', 'other-boss-token', 'other-cleanup-boss');
});
beforeEach(async () => {
  await env.DB.prepare('DELETE FROM boss_destinations WHERE boss_id = ?').bind(bossId).run();
  await env.DB.prepare('DELETE FROM boss_devices WHERE boss_id = ?').bind(bossId).run();
  await env.DB.prepare(`INSERT INTO boss_devices (id, boss_id, device_token, bundle_id, environment) VALUES
    ('cleanup-device', ?, ?, 'app', 'sandbox'), ('kept-device', ?, '11223344', 'app', 'sandbox')`)
    .bind(bossId, deviceToken, bossId).run();
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, target, label) VALUES
    ('cleanup-destination', ?, 'apns', '{"device_id":"cleanup-device"}', 'Push'),
    ('kept-destination', ?, 'apns', '{"device_id":"kept-device"}', 'Push'),
    ('kept-native', ?, 'native_live', '{}', 'Native')`).bind(bossId, bossId, bossId).run();
});
afterEach(() => vi.restoreAllMocks());

async function message(): Promise<MessageRow> {
  const row = await env.DB.prepare(`INSERT INTO messages (agent_id, direction, mode, body, priority)
    VALUES ('test-agent-id', 'agent_to_boss', 'async', 'cleanup', 'high') RETURNING *`).first<MessageRow>();
  if (!row) throw new Error('fixture insert failed');
  return row;
}

it('keeps device and destination when another boss attempts deletion', async () => {
  const response = await SELF.fetch(`https://test/api/boss/devices/${deviceToken}`, {
    method: 'DELETE', headers: { Authorization: 'Bearer other-boss-token' },
  });
  expect(response.status).toBe(200);
  expect(await env.DB.prepare("SELECT id FROM boss_devices WHERE id = 'cleanup-device'").first()).not.toBeNull();
  expect(await env.DB.prepare("SELECT id FROM boss_destinations WHERE id = 'cleanup-destination'").first()).not.toBeNull();
});

it.each(['api', 'notify', 'destination'])('cleans only the removed device inventory via %s', async path => {
  const row = await message();
  await env.DB.prepare("INSERT INTO destination_routes (destination_id, external_thread_id) VALUES ('cleanup-destination', '123')").run();
  await env.DB.prepare("INSERT INTO message_deliveries (message_id, destination_id) VALUES (?, 'cleanup-destination')").bind(row.id).run();
  vi.spyOn(apns, 'hasApnsConfig').mockReturnValue(true);
  vi.spyOn(apns, 'sendPush').mockImplementation(async (_env, token) => token === deviceToken
    ? { ok: false, prune: true, reason: 'Unregistered' } : { ok: true, prune: false });
  if (path === 'api') {
    const response = await SELF.fetch(`https://test/api/boss/devices/${deviceToken.toUpperCase()}`, {
      method: 'DELETE', headers: { Authorization: `Bearer ${bossToken}` },
    });
    expect(response.status).toBe(200);
  } else if (path === 'notify') {
    await notifyBossAgents(env, row.agent_id, row);
  } else {
    const destination = (await resolveDestinations(env, row)).find(item => item.id === 'cleanup-destination');
    if (!destination) throw new Error('missing push destination');
    await expect(sendDestination(env, destination, row)).rejects.toThrow('Unregistered');
  }
  expect(await env.DB.prepare("SELECT id FROM boss_devices WHERE id = 'cleanup-device'").first()).toBeNull();
  expect(await env.DB.prepare('SELECT id FROM boss_destinations WHERE boss_id = ? ORDER BY id').bind(bossId).all())
    .toMatchObject({ results: [{ id: 'kept-destination' }, { id: 'kept-native' }] });
  expect(await env.DB.prepare("SELECT id FROM boss_devices WHERE id = 'kept-device'").first()).not.toBeNull();
  expect(await env.DB.prepare("SELECT id FROM destination_routes WHERE destination_id = 'cleanup-destination'").first()).toBeNull();
  expect(await env.DB.prepare('SELECT id FROM message_deliveries WHERE message_id = ?').bind(row.id).first()).toBeNull();
});
