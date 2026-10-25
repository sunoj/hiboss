// Boss-minted agent keys: managers cannot reach boss-linked or is_admin agents, and a key
// lives only while its minting boss could still mint it, including keys it self-mints
// (audit round 2: BG1, BG2, BG3).
// Runs against Worker/D1 via SELF; depends on shared seeds and real auth middleware.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import type { AgentKey } from './types';
import migration from '../../migrations/0064_agent_key_minter.sql?raw';

beforeAll(seedDatabase);
const base = 'https://test.local/api';
async function request(path: string, token: string, method = 'GET', body?: unknown): Promise<Response> {
  return SELF.fetch(base + path, {
    method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
async function agent(name: string): Promise<{ id: string; token: string }> {
  const token = `hb_${name}`;
  const hash = await hashApiKey(token);
  const row = await env.DB.prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id')
    .bind(name, hash).first<{ id: string }>();
  if (!row) throw new Error('seed failed');
  await env.DB.prepare("INSERT INTO agent_keys (agent_id, key_hash, label) VALUES (?, ?, 'own')").bind(row.id, hash).run();
  return { id: row.id, token };
}
async function grant(bossId: string, agentId: string): Promise<void> {
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(bossId, agentId).run();
}
async function mint(agentId: string, token: string): Promise<Response> {
  return request(`/boss/agents/${agentId}/keys`, token, 'POST', { label: 'minted' });
}
async function minted(agentId: string, token: string): Promise<string> {
  const response = await mint(agentId, token);
  expect(response.status).toBe(201);
  return (await response.json() as AgentKey & { key: string }).key;
}
const live = async (key: string): Promise<number> => (await request('/agents/me', key)).status;

it('refuses a manager the key and signing surface of a boss-linked agent', async () => {
  const plain = await agent('bm-plain');
  const linked = await agent('bm-linked');
  const manager = await seedBossToken('BM manager', 'manager', 'bm-manager');
  await seedBossToken('BM admin', 'admin', 'bm-admin');
  await env.DB.prepare("INSERT INTO bosses (name, role, agent_id) VALUES ('BM linked admin', 'admin', ?)").bind(linked.id).run();
  await grant(manager, plain.id);
  await grant(manager, linked.id);
  expect((await mint(plain.id, 'bm-manager')).status).toBe(201);
  expect((await mint(linked.id, 'bm-manager')).status).toBe(403);
  expect((await request(`/boss/agents/${linked.id}/keys`, 'bm-manager')).status).toBe(403);
  expect((await request(`/boss/agents/${linked.id}/signing-keys`, 'bm-manager', 'DELETE')).status).toBe(403);
  expect((await mint(linked.id, 'bm-admin')).status).toBe(201);
});

it('refuses a manager the key surface of an is_admin agent', async () => {
  const capable = await agent('bm-capable');
  await env.DB.prepare('UPDATE api_keys SET is_admin = 1 WHERE id = ?').bind(capable.id).run();
  const manager = await seedBossToken('BM manager 2', 'manager', 'bm-manager-2');
  await grant(manager, capable.id);
  expect((await mint(capable.id, 'bm-manager-2')).status).toBe(403);
});

it('revokes a manager-minted key when the grant is removed, keeping the agent own key', async () => {
  const a = await agent('bm-grant');
  const manager = await seedBossToken('BM manager 3', 'manager', 'bm-manager-3');
  await seedBossToken('BM admin 3', 'admin', 'bm-admin-3');
  await grant(manager, a.id);
  const key = await minted(a.id, 'bm-manager-3');
  expect(await live(key)).toBe(200);
  expect((await request(`/bosses/${manager}/access/${a.id}`, 'bm-admin-3', 'DELETE')).status).toBe(200);
  expect(await live(key)).toBe(401);
  expect(await live(a.token)).toBe(200);
  const audit = await env.DB.prepare(`SELECT actor_type FROM audit_log WHERE action = 'agent_key.revoke'
    AND resource_type = 'agent_key' AND details LIKE ?`).bind(`%${a.id}%`).all();
  expect(audit.results).toEqual([{ actor_type: 'system' }]);
});

it('revokes a manager-minted key on demotion and when the agent becomes protected', async () => {
  const a = await agent('bm-demote');
  const b = await agent('bm-elevate');
  const manager = await seedBossToken('BM manager 4', 'manager', 'bm-manager-4');
  await seedBossToken('BM admin 4', 'admin', 'bm-admin-4');
  await grant(manager, a.id);
  await grant(manager, b.id);
  const keyA = await minted(a.id, 'bm-manager-4');
  const keyB = await minted(b.id, 'bm-manager-4');
  expect((await request(`/boss/agents/${b.id}/config`, 'bm-admin-4', 'PATCH', { admin: true })).status).toBe(200);
  expect(await live(keyB)).toBe(401);
  expect(await live(keyA)).toBe(200);
  expect((await request(`/bosses/${manager}`, 'bm-admin-4', 'PATCH', { role: 'viewer' })).status).toBe(200);
  expect(await live(keyA)).toBe(401);
});

it('revokes keys minted by an archived or deleted boss', async () => {
  const a = await agent('bm-archive');
  const b = await agent('bm-delete');
  const minter = await seedBossToken('BM minter admin', 'admin', 'bm-minter');
  const gone = await seedBossToken('BM gone manager', 'manager', 'bm-gone');
  await seedBossToken('BM keeper admin', 'admin', 'bm-keeper');
  await grant(gone, b.id);
  const keyA = await minted(a.id, 'bm-minter');
  const keyB = await minted(b.id, 'bm-gone');
  expect((await request(`/bosses/${minter}/archive`, 'bm-keeper', 'POST')).status).toBe(200);
  expect(await live(keyA)).toBe(401);
  expect((await request(`/bosses/${gone}`, 'bm-keeper', 'DELETE')).status).toBe(200);
  expect(await live(keyB)).toBe(401);
});

it('revokes a manager-minted key when a boss is linked to the agent', async () => {
  const a = await agent('bm-link-later');
  const manager = await seedBossToken('BM manager 5', 'manager', 'bm-manager-5');
  await seedBossToken('BM admin 5', 'admin', 'bm-admin-5');
  await grant(manager, a.id);
  const key = await minted(a.id, 'bm-manager-5');
  const created = await request('/bosses', 'bm-admin-5', 'POST', { name: 'BM agent boss', role: 'admin', agent_id: a.id });
  expect(created.status).toBe(201);
  expect(await live(key)).toBe(401);
  expect(await live(a.token)).toBe(200);
});

it('revokes keys self-minted with a boss-minted bearer along with their parent', async () => {
  const a = await agent('bm-lineage');
  const manager = await seedBossToken('BM manager 6', 'manager', 'bm-manager-6');
  await seedBossToken('BM admin 6', 'admin', 'bm-admin-6');
  await grant(manager, a.id);
  const parent = await minted(a.id, 'bm-manager-6');
  const child = await request('/agents/me/keys', parent, 'POST', { label: 'child' });
  expect(child.status).toBe(201);
  const childKey = (await child.json() as { key: string }).key;
  const own = await request('/agents/me/keys', a.token, 'POST', { label: 'own child' });
  const ownKey = (await own.json() as { key: string }).key;
  expect((await request(`/bosses/${manager}/access/${a.id}`, 'bm-admin-6', 'DELETE')).status).toBe(200);
  expect([await live(parent), await live(childKey)]).toEqual([401, 401]);
  expect([await live(a.token), await live(ownKey)]).toEqual([200, 200]);
});

// Runs last: replays the migration's data statements over this file's database.
it('backfills boss mints from the audit but never an agent first key', async () => {
  const a = await agent('bm-joined');
  const approver = await seedBossToken('BM approver', 'admin', 'bm-approver');
  const first = await env.DB.prepare('SELECT id FROM agent_keys WHERE agent_id = ?').bind(a.id).first<string>('id');
  const later = await minted(a.id, 'bm-approver');
  const laterId = await env.DB.prepare('SELECT id FROM agent_keys WHERE key_hash = ?').bind(await hashApiKey(later)).first<string>('id');
  await env.DB.prepare(`INSERT INTO audit_log (actor_type, actor_id, action, resource_type, resource_id, details)
    VALUES ('boss', ?, 'agent_key.mint', 'agent_key', ?, '{}')`).bind(approver, first).run();
  await env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?").bind(approver).run();
  await env.DB.prepare('UPDATE agent_keys SET minted_by_boss_id = NULL WHERE agent_id = ?').bind(a.id).run();
  const data = migration.replace(/^--.*$/gm, '').split(';').map(sql => sql.trim())
    .filter(sql => sql && !sql.startsWith('ALTER') && !sql.startsWith('CREATE INDEX'));
  await env.DB.batch(data.map(sql => env.DB.prepare(sql)));
  const rows = await env.DB.prepare('SELECT id, minted_by_boss_id AS minter FROM agent_keys WHERE agent_id = ?').bind(a.id).all();
  expect(rows.results).toEqual(expect.arrayContaining([{ id: first, minter: null }, { id: laterId, minter: approver }]));
  expect([await live(a.token), await live(later)]).toEqual([200, 401]);
});
