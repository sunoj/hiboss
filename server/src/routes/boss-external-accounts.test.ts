// External identity ownership, inbound precedence, and admin synchronization flows.
// Depends on authenticated Worker routes and real D1 fixtures; no provider traffic.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import app from '../index';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { resolveBossForChannel } from './webhook-helpers';
beforeAll(async () => {
  await seedDatabase();
  for (const role of ['admin', 'manager', 'viewer']) await seedBossToken(role, role, `identity-${role}`, `identity-${role}`);
});
async function request(role: string, path: string, method = 'GET', body?: unknown): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request(`https://test/api/${path}`, { method,
    headers: { Authorization: `Bearer identity-${role}`, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }), env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
const own = 'boss/me/external-accounts';
it.each(['telegram', 'discord'] as const)('prefers new %s identities and falls back only when absent', async provider => {
  const column = provider === 'telegram' ? 'telegram_user_id' : 'discord_user_id';
  await env.DB.prepare(`UPDATE bosses SET ${column} = '100' WHERE id = 'identity-admin'`).run();
  expect((await resolveBossForChannel(env, provider, '100', true)).boss?.id).toBe('identity-admin');
  await env.DB.prepare("INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id) VALUES ('identity-manager', ?, '100')").bind(provider).run();
  expect((await resolveBossForChannel(env, provider, '100', true)).boss?.id).toBe('identity-manager');
});
it('allows own account CRUD, hides cross-boss deletes, and blocks viewers', async () => {
  const response = await request('manager', own, 'POST', { provider: 'telegram', provider_user_id: '200' });
  expect(response.status).toBe(201);
  const { external_account: account } = await response.json() as { external_account: { id: string } };
  expect((await request('admin', `${own}/${account.id}`, 'DELETE')).status).toBe(404);
  expect((await request('manager', own)).status).toBe(200);
  expect(await (await request('viewer', own)).json()).toEqual({ external_accounts: [] });
  expect((await request('viewer', own, 'POST', { provider: 'discord', provider_user_id: '201' })).status).toBe(403);
  expect((await request('viewer', `${own}/${account.id}`, 'DELETE')).status).toBe(403);
  expect((await request('admin', own, 'POST', { provider: 'telegram', provider_user_id: '200' })).status).toBe(409);
  expect((await request('manager', `${own}/${account.id}`, 'DELETE')).status).toBe(200);
});
it('clears matching legacy fallback on deletion and restricts the admin surface', async () => {
  await env.DB.prepare("UPDATE bosses SET discord_user_id = '300' WHERE id = 'identity-manager'").run();
  const response = await request('admin', 'bosses/identity-manager/external-accounts', 'POST', { provider: 'discord', provider_user_id: '300' });
  expect(response.status).toBe(201);
  const { external_account: account } = await response.json() as { external_account: { id: string } };
  expect((await request('manager', 'bosses/identity-admin/external-accounts')).status).toBe(403);
  expect((await request('manager', `${own}/${account.id}`, 'DELETE')).status).toBe(200);
  expect((await resolveBossForChannel(env, 'discord', '300', true)).error).toBe('unknown sender');
});
it('keeps existing admin identity edits synchronized and rejects account theft', async () => {
  expect((await request('admin', 'bosses/identity-manager', 'PATCH', { telegram_user_id: '401' })).status).toBe(200);
  expect((await resolveBossForChannel(env, 'telegram', '401', true)).boss?.id).toBe('identity-manager');
  expect((await request('admin', 'bosses/identity-manager', 'PATCH', { telegram_user_id: '402' })).status).toBe(200);
  expect((await resolveBossForChannel(env, 'telegram', '401', true)).error).toBe('unknown sender');
  // PATCH preserves the parent's uncaught constraint response, with the batch rolled back.
  const conflict = await request('admin', 'bosses/identity-admin', 'PATCH', { telegram_user_id: '402' });
  expect(conflict.status).toBe(500);
  expect(await conflict.json()).toMatchObject({ error: 'internal server error', request_id: expect.any(String) });
  expect((await resolveBossForChannel(env, 'telegram', '402', true)).boss?.id).toBe('identity-manager');
  expect((await request('admin', own, 'POST', { provider: 'email', provider_user_id: '400' })).status).toBe(400);
});
