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

it('admin creates a provider without ever echoing credentials', async () => {
  const response = await request('admin', 'providers', 'POST', {
    provider: 'telegram', label: 'Bot', credentials: { bot_token: 'secret-token' },
  });
  expect(response.status).toBe(201);
  const text = await response.text();
  expect(text).not.toContain('secret-token');
  expect(text).not.toContain('credentials');
  expect(await (await request('admin', 'providers')).text()).not.toContain('secret-token');
});
it('manager owns mutations; admin cannot modify another boss destination', async () => {
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('api-provider', 'telegram', 'Bot', '{}')").run();
  const response = await request('manager', 'destinations', 'POST', {
    kind: 'telegram_chat', provider_id: 'api-provider', target: { chat_id: '-123' }, label: 'Team',
  });
  expect(response.status).toBe(201);
  const { destination } = await response.json() as { destination: { id: string } };
  const path = `destinations/${destination.id}`;
  expect((await request('admin', path, 'PATCH', { enabled: false })).status).toBe(404);
  expect((await request('admin', path, 'DELETE')).status).toBe(404);
  expect((await request('manager', path, 'PATCH', { enabled: false, min_priority: 'high', honours_quiet_hours: false, label: 'Updated' })).status).toBe(200);
  await env.DB.prepare("INSERT INTO destination_routes (destination_id, project, external_thread_id) VALUES (?, 'project', '10')").bind(destination.id).run();
  const list = await (await request('manager', 'destinations')).json() as { destinations: { route_count: number; provider_label: string }[] };
  expect(list.destinations[0]).toMatchObject({ route_count: 1, provider_label: 'Bot' });
  expect((await request('manager', path, 'DELETE')).status).toBe(200);
  expect(await env.DB.prepare('SELECT id FROM destination_routes WHERE destination_id = ?').bind(destination.id).first()).toBeNull();
});
it('viewers read only and non-admins cannot list or create providers', async () => {
  expect((await request('viewer', 'destinations')).status).toBe(200);
  for (const method of ['POST', 'PATCH', 'DELETE']) {
    expect((await request('viewer', method === 'POST' ? 'destinations' : 'destinations/missing', method, {})).status).toBe(403);
  }
  for (const role of ['manager', 'viewer']) for (const method of ['GET', 'POST']) {
    expect((await request(role, 'providers', method, method === 'POST' ? {} : undefined)).status).toBe(403);
  }
});
it('rejects email, invalid priorities, provider mismatch, and credential injection', async () => {
  expect((await request('admin', 'providers', 'POST', { provider: 'email', label: 'Email', credentials: {} })).status).toBe(400);
  expect((await request('manager', 'destinations', 'POST', { kind: 'email', label: 'Email', target: {} })).status).toBe(400);
  expect((await request('manager', 'destinations/missing', 'PATCH', { min_priority: 'urgent' })).status).toBe(400);
  expect((await request('manager', 'destinations', 'POST', { kind: 'discord_channel', provider_id: 'api-provider', label: 'Bad', target: { channel_id: '123' } })).status).toBe(400);
  expect((await request('manager', 'destinations', 'POST', { kind: 'telegram_chat', provider_id: 'api-provider', label: 'Bad', target: { chat_id: '123', bot_token: 'override' } })).status).toBe(400);
});
