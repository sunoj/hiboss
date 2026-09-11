// Protects the pre-extraction boss HTTP contract and shared preference validation.
// Uses authenticated Worker requests and D1, including persisted error-path assertions.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import app from '../index';
import { seedDatabase, seedBossToken } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Admin', 'admin', 'contract-admin', 'contract-admin');
  await seedBossToken('Target', 'manager', 'contract-target', 'contract-target');
});
async function request(path: string, body?: unknown, method = 'PATCH', token = 'contract-admin'): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request('https://test/api/' + path, {
    method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
it.each([
  [{ role: 'junk' }, 'invalid role'],
  [{ role: ' admin ' }, 'invalid role'],
  [{ name: ' ' }, 'name is required'],
  [{ name: 123 }, 'no valid fields to update'],
  [{ role: 123 }, 'no valid fields to update'],
  [{ agent_id: 123 }, 'agent_id must be a string or null'],
  [{ telegram_user_id: 123, preferences: [] }, 'telegram_user_id must be a string or null'],
  [{ discord_user_id: false, agent_id: 123 }, 'discord_user_id must be a string or null'],
  [{ preferences: [] }, 'preferences must be an object or null'],
  [{ preferences: { quiet_hours: { timezone: 'UTC' } } }, 'quiet_hours must have start and end time strings (HH:MM)'],
])('preserves text PATCH errors for %j', async (payload, error) => {
  const before = await env.DB.prepare("SELECT * FROM bosses WHERE id = 'contract-target'").first();
  const response = await request('bosses/contract-target', payload);
  expect(response.status).toBe(400);
  expect(response.headers.get('Content-Type')).toBe('text/plain; charset=UTF-8');
  expect(await response.text()).toBe(error);
  expect(await env.DB.prepare("SELECT * FROM bosses WHERE id = 'contract-target'").first()).toEqual(before);
});
it.each([123, null, false, {}, []])('ignores non-string role %j while updating other fields', async role => {
  const response = await request('bosses/contract-target', { name: '  Two  ', role });
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ name: 'Two', role: 'manager' });
});
it('preserves schema-default IDs, raw preference responses, and both account writes', async () => {
  const response = await request('bosses', { name: ' Created ', role: 123, telegram_user_id: ' 123 ', discord_user_id: ' 456 ' }, 'POST');
  expect(response.status).toBe(201);
  const created = await response.json() as { id: string; name: string; role: string };
  expect(created).toMatchObject({ name: 'Created', role: 'admin' });
  expect(created.id).toMatch(/^[a-f0-9]{32}$/);
  expect((await env.DB.prepare('SELECT provider FROM boss_external_accounts WHERE boss_id = ?').bind(created.id).all()).results).toHaveLength(2);
  const update = await request(`bosses/${created.id}`, { preferences: {} });
  expect(update.status).toBe(200);
  expect(await update.json()).toMatchObject({ preferences: '{}' });
  const conflict = await request('bosses', { name: 'Duplicate', telegram_user_id: '123' }, 'POST');
  expect(conflict.status).toBe(409);
  expect(conflict.headers.get('Content-Type')).toBe('text/plain; charset=UTF-8');
  expect(await conflict.text()).toBe('external account already linked');
});
it.each(['preferred_channel', 'notify_priorities'])('rejects removed %s on both preference paths without persistence', async key => {
  for (const [path, method, body] of [
    ['bosses/contract-admin', 'PATCH', { preferences: { [key]: 'junk' } }],
    ['boss/me/preferences', 'PUT', { [key]: 'junk' }],
  ] as const) {
    const before = await env.DB.prepare("SELECT preferences FROM bosses WHERE id = 'contract-admin'").first();
    const response = await request(path, body, method);
    expect(response.status).toBe(400);
    expect(await response.text()).toBe('use destination notification settings');
    expect(await env.DB.prepare("SELECT preferences FROM bosses WHERE id = 'contract-admin'").first()).toEqual(before);
  }
});
it('uses the same quiet-hours validator and prunes removed stored keys on self updates', async () => {
  const bad = await request('boss/me/preferences', { quiet_hours: { timezone: 'UTC' } }, 'PUT');
  expect(bad.status).toBe(400);
  expect(await bad.text()).toBe('quiet_hours must have start and end time strings (HH:MM)');
  await env.DB.prepare("UPDATE bosses SET preferences = ? WHERE id = 'contract-admin'")
    .bind(JSON.stringify({ preferred_channel: 'junk', notify_priorities: ['junk'], timezone: 'UTC' })).run();
  const response = await request('boss/me/preferences', { quiet_hours: { start: '22:00', end: '08:00' } }, 'PUT');
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ timezone: 'UTC', quiet_hours: { start: '22:00', end: '08:00' } });
});
