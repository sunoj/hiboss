// Boss destination/provider API ownership, validation, and credential secrecy flows.
// Depends on the real authenticated Worker router and D1 fixture storage.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import app from '../../index';
import { seedDatabase, seedBossToken } from '../../test-helpers';

beforeAll(async () => {
  await seedDatabase();
  for (const role of ['admin', 'manager', 'viewer']) await seedBossToken(role, role, `token-${role}`, role);
});
async function request(role: string, path: string, method = 'GET', body?: unknown): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request(`https://test/api/boss/${path}`, {
    method, headers: { Authorization: `Bearer token-${role}`, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

it('manager owns mutations; admin cannot modify another boss destination', async () => {
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, target, label)
    VALUES ('api-native', 'manager', 'native_live', '{}', 'Native')`).run();
  const path = 'destinations/api-native';
  expect((await request('admin', path, 'PATCH', { enabled: false })).status).toBe(404);
  expect((await request('admin', path, 'DELETE')).status).toBe(404);
  expect((await request('manager', path, 'PATCH', { enabled: false, min_priority: 'high', honours_quiet_hours: false, label: 'Updated' })).status).toBe(200);
  expect((await request('manager', path, 'DELETE')).status).toBe(200);
  expect(await env.DB.prepare('SELECT id FROM boss_destinations WHERE id = ?').bind('api-native').first()).toBeNull();
});
it('viewers can read destination inventory only', async () => {
  expect((await request('viewer', 'destinations')).status).toBe(200);
  for (const method of ['PATCH', 'DELETE']) {
    expect((await request('viewer', 'destinations/missing', method, {})).status).toBe(403);
  }
});
it('rejects invalid priorities', async () => {
  expect((await request('manager', 'destinations/missing', 'PATCH', { min_priority: 'urgent' })).status).toBe(400);
});
