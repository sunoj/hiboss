// Public key lifecycle, bearer compatibility, revocation and authorization coverage.
// Runs against Worker/D1 via SELF; depends on shared seeds and real auth middleware.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import type { AgentKey } from './types';

beforeAll(seedDatabase);
const base = 'https://test.local/api';
const headers = (token: string) => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
async function request(path: string, token: string, method = 'GET', body?: unknown): Promise<Response> {
  return SELF.fetch(base + path, { method, headers: headers(token), body: body === undefined ? undefined : JSON.stringify(body) });
}
async function agent(name: string, migrated = true): Promise<{ id: string; token: string; keyId: string }> {
  const token = `hb_${name}`;
  const hash = await hashApiKey(token);
  const row = await env.DB.prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id')
    .bind(name, hash).first<{ id: string }>();
  if (!row) throw new Error('seed failed');
  const keyId = crypto.randomUUID();
  if (migrated) await env.DB.prepare("INSERT INTO agent_keys (id, agent_id, key_hash, label) VALUES (?, ?, ?, 'migrated')")
    .bind(keyId, row.id, hash).run();
  return { id: row.id, token, keyId };
}

it('authenticates an unchanged migrated bearer, exposes its key ID and throttles key usage', async () => {
  const a = await agent('migrated-auth');
  const response = await request('/agents/me', a.token);
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ id: a.id, agent_key_id: a.keyId });
  await env.DB.prepare(`UPDATE agent_keys SET last_used_at = datetime('now', '+1 hour') WHERE id = ?`).bind(a.keyId).run();
  const before = await env.DB.prepare('SELECT last_used_at FROM agent_keys WHERE id = ?').bind(a.keyId).first();
  expect((await request('/sessions', a.token)).status).toBe(200);
  expect(await env.DB.prepare('SELECT last_used_at FROM agent_keys WHERE id = ?').bind(a.keyId).first()).toEqual(before);
  expect(await env.DB.prepare('SELECT last_used_at FROM api_keys WHERE id = ?').bind(a.id).first()).toMatchObject({ last_used_at: expect.any(String) });
});

it('falls back only for a hash absent from agent_keys in both authentication surfaces', async () => {
  const a = await agent('fallback-auth', false);
  expect(await (await request('/agents/me', a.token)).json()).toMatchObject({ id: a.id, agent_key_id: null });
  expect((await request('/sessions', a.token)).status).toBe(200);
  await env.DB.prepare("INSERT INTO agent_keys (agent_id, key_hash, label, revoked_at) VALUES (?, ?, 'revoked', datetime('now'))")
    .bind(a.id, await hashApiKey(a.token)).run();
  expect((await request('/agents/me', a.token)).status).toBe(401);
  expect((await request('/sessions', a.token)).status).toBe(401);
});

it('mints once, lists metadata only, guards the last current key, and audits changes', async () => {
  const a = await agent('self-keys');
  const path = '/agents/me/keys';
  expect((await request(`${path}/${a.keyId}`, a.token, 'DELETE')).status).toBe(409);
  const minted = await request(path, a.token, 'POST', { label: 'Mac' });
  expect(minted.status).toBe(201);
  const key = await minted.json() as AgentKey & { key: string };
  expect(await (await request('/agents/me', key.key)).json()).toMatchObject({ id: a.id, agent_key_id: key.id });
  const listed = await (await request(path, a.token)).json() as { keys: AgentKey[]; current_key_id: string };
  expect(listed.current_key_id).toBe(a.keyId);
  expect(listed.keys).toHaveLength(2);
  expect(JSON.stringify(listed)).not.toContain(key.key);
  expect(JSON.stringify(listed)).not.toContain('key_hash');
  expect((await request(`${path}/${a.keyId}`, a.token, 'DELETE')).status).toBe(200);
  expect((await request('/agents/me', a.token)).status).toBe(401);
  expect((await request(`${path}/${key.id}`, key.key, 'DELETE')).status).toBe(409);
  const audit = await env.DB.prepare("SELECT action FROM audit_log WHERE actor_id = ? AND action LIKE 'agent_key.%'").bind(a.id).all();
  expect(audit.results.map(row => row.action)).toEqual(expect.arrayContaining(['agent_key.mint', 'agent_key.list', 'agent_key.revoke']));
});

it('rejects cross-agent revocation and malformed key labels', async () => {
  const a = await agent('owner-a');
  const b = await agent('owner-b');
  expect((await request(`/agents/me/keys/${b.keyId}`, a.token, 'DELETE')).status).toBe(404);
  for (const body of [null, [], {}, { label: '' }, { label: 123 }, { label: 'x'.repeat(101) }]) {
    expect((await request('/agents/me/keys', a.token, 'POST', body)).status).toBe(400);
  }
});

it('uses is_admin independently of workflow role and prevents self elevation', async () => {
  const a = await agent('admin-capability');
  await env.DB.prepare("UPDATE api_keys SET role = 'admin' WHERE id = ?").bind(a.id).run();
  expect((await request('/keys', a.token)).status).toBe(403);
  await env.DB.prepare("UPDATE api_keys SET is_admin = 1, role = 'worker' WHERE id = ?").bind(a.id).run();
  expect((await request('/keys', a.token)).status).toBe(200);
  expect((await request('/agents/me/config', a.token, 'PUT', { role: 'admin' })).status).toBe(400);
});

it('allows accessible managers and all-agent admins, blocks viewers and ungranted bosses', async () => {
  const a = await agent('boss-managed');
  const manager = await seedBossToken('Key manager', 'manager', 'manager-keys');
  await seedBossToken('Key admin', 'admin', 'admin-keys');
  const viewer = await seedBossToken('Key viewer', 'viewer', 'viewer-keys');
  const path = `/boss/agents/${a.id}/keys`;
  expect((await request(path, 'manager-keys')).status).toBe(404);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?), (?, ?)')
    .bind(manager, a.id, viewer, a.id).run();
  for (const method of ['GET', 'POST', 'DELETE']) {
    const route = method === 'DELETE' ? `${path}/${a.keyId}` : path;
    expect((await request(route, 'viewer-keys', method, method === 'POST' ? { label: 'box' } : undefined)).status).toBe(403);
  }
  for (const token of ['manager-keys', 'admin-keys']) {
    expect((await request(path, token)).status).toBe(200);
    const response = await request(path, token, 'POST', { label: 'Linux' });
    expect(response.status).toBe(201);
    const key = await response.json() as AgentKey & { key: string };
    expect((await request(`${path}/${key.id}`, token, 'DELETE')).status).toBe(200);
    expect((await request('/agents/me', key.key)).status).toBe(401);
  }
  expect((await request(`${path}/${a.keyId}`, 'manager-keys', 'DELETE')).status).toBe(200);
  expect((await request(path, 'admin-keys', 'POST', { label: 'Recovery' })).status).toBe(201);
});
