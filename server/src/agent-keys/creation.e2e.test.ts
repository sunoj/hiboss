// Exercises all identity creation surfaces against the real Worker and D1.
// Verifies credentials authenticate while the retained identity hash stays NULL.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { approveJoinRequest } from '../routes/join-helpers';
import joinMigration from '../../migrations/0018_join_requests.sql?raw';

beforeAll(async () => {
  await seedDatabase();
  for (const statement of joinMigration.replace(/^--.*$/gm, '').split(';').filter(sql => sql.trim())) {
    await env.DB.prepare(statement).run();
  }
  await env.DB.prepare('DELETE FROM api_keys').run();
});
const base = 'https://test.local/api';
interface Grant { id: string; key: string }
async function assertGrant(grant: Grant): Promise<void> {
  expect(await env.DB.prepare('SELECT key_hash FROM api_keys WHERE id = ?').bind(grant.id).first()).toEqual({ key_hash: null });
  const keys = await env.DB.prepare('SELECT id FROM agent_keys WHERE agent_id = ?').bind(grant.id).all<{ id: string }>();
  expect(keys.results).toHaveLength(1);
  const response = await SELF.fetch(`${base}/agents/me`, { headers: { Authorization: `Bearer ${grant.key}` } });
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ id: grant.id, agent_key_id: keys.results[0].id });
}
async function post(path: string, body: unknown, token?: string): Promise<Response> {
  return SELF.fetch(base + path, { method: 'POST', body: JSON.stringify(body),
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) } });
}

it('bootstrap and admin creation write only independent credentials', async () => {
  const response = await post('/bootstrap', {});
  expect(response.status).toBe(201);
  const bootstrap = await response.json() as Grant;
  await assertGrant(bootstrap);
  await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(bootstrap.id).run();
  const created = await post('/keys', { name: 'admin-created' }, bootstrap.key);
  expect(created.status).toBe(201);
  await assertGrant(await created.json() as Grant);
});

it('boss and provider approvals create keys for new identities', async () => {
  await seedBossToken('Creation admin', 'admin', 'creation-boss');
  for (const provider of ['boss', 'callback']) {
    const pending = await post('/join', { name: `approved-${provider}` });
    expect(pending.status).toBe(201);
    const { request_id, poll_token } = await pending.json() as { request_id: string; poll_token: string };
    if (provider === 'boss') expect((await post(`/boss/join-requests/${request_id}/approve`, {}, 'creation-boss')).status).toBe(200);
    else expect((await approveJoinRequest(env, request_id)).statusCode).toBe(200);
    const poll = await SELF.fetch(`${base}/join/status?token=${poll_token}`);
    const grant = await poll.json() as { agent_id: string; key: string };
    await assertGrant({ id: grant.agent_id, key: grant.key });
  }
});

it('first-agent join creates an independent credential without enrolment changes', async () => {
  await env.DB.prepare('DELETE FROM join_requests').run();
  await env.DB.prepare('DELETE FROM boss_agent_access').run();
  await env.DB.prepare('DELETE FROM api_keys').run();
  const response = await post('/join', { name: 'first-join' });
  expect(response.status).toBe(201);
  const grant = await response.json() as { agent_id: string; key: string; status: string };
  expect(grant.status).toBe('approved');
  await assertGrant({ id: grant.agent_id, key: grant.key });
});
