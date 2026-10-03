// Archive API integration coverage: reversible state, authorization, and retained history.
// Exercises real Worker routes and D1 storage through cloudflare:test.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, seedBossToken, seedDatabase } from '../test-helpers';

const ADMIN = 'archive-admin-token';
const MANAGER = 'archive-manager-token';
let admin: string;
let manager: string;
const headers = (token = ADMIN): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
const post = (id: string, action: string, token = ADMIN): Promise<Response> => SELF.fetch(`https://test.local/api/bosses/${id}/${action}`, { method: 'POST', headers: headers(token) });

beforeAll(async () => {
  await seedDatabase();
  admin = await seedBossToken('Admin', 'admin', ADMIN);
  manager = await seedBossToken('Manager', 'manager', MANAGER);
  await env.DB.prepare('INSERT INTO boss_agent_access VALUES (?, ?)').bind(manager, 'test-agent-id').run();
  await env.DB.prepare("INSERT INTO boss_clients (id, boss_id, kind, label) VALUES ('archive-client', ?, 'macos', 'Retained client')").bind(manager).run();
  await env.DB.prepare("UPDATE boss_tokens SET client_id = 'archive-client' WHERE boss_id = ?").bind(manager).run();
  await env.DB.prepare("INSERT INTO boss_external_accounts (boss_id, provider, provider_user_id) VALUES (?, 'telegram', '9988')").bind(manager).run();
  await env.DB.prepare("INSERT INTO audit_log (id, actor_type, actor_id, action, resource_type, resource_id) VALUES ('archive-prior-audit', 'boss', ?, 'boss.create', 'boss', ?)").bind(admin, manager).run();
  await seedBossToken('Viewer', 'viewer', 'archive-viewer-token');
});

it('archives and restores without changing grants, clients, tokens, or existing audit rows', async () => {
  const tables = ['boss_agent_access', 'boss_clients', 'boss_tokens', 'boss_external_accounts'];
  const before = await Promise.all(tables.map(table => env.DB.prepare(`SELECT * FROM ${table} WHERE boss_id = ?`).bind(manager).all()));
  expect((await post(manager, 'archive')).status).toBe(200);
  const archived = await env.DB.prepare('SELECT archived_at FROM bosses WHERE id = ?').bind(manager).first<{ archived_at: string }>();
  expect(archived?.archived_at).toEqual(expect.any(String));
  const list = await SELF.fetch('https://test.local/api/bosses', { headers: headers() });
  expect(await list.json()).toMatchObject({ bosses: expect.arrayContaining([
    expect.objectContaining({ id: manager, archived_at: archived?.archived_at }),
    expect.objectContaining({ id: admin, archived_at: null }),
  ]) });
  const detail = await SELF.fetch(`https://test.local/api/bosses/${manager}`, { headers: headers() });
  expect(await detail.json()).toMatchObject({ id: manager, archived_at: archived?.archived_at });
  expect((await SELF.fetch('https://test.local/api/boss/me', { headers: headers(MANAGER) })).status).toBe(401);
  const after = await Promise.all(tables.map(table => env.DB.prepare(`SELECT * FROM ${table} WHERE boss_id = ?`).bind(manager).all()));
  expect(after.map(result => result.results)).toEqual(before.map(result => result.results));
  expect((await post(manager, 'archive')).status).toBe(409);
  expect((await post(manager, 'restore')).status).toBe(200);
  expect((await SELF.fetch('https://test.local/api/boss/me', { headers: headers(MANAGER) })).status).toBe(200);
  const audit = await env.DB.prepare("SELECT action FROM audit_log WHERE resource_id = ? AND action IN ('boss.archive', 'boss.restore') ORDER BY rowid").bind(manager).all();
  expect(audit.results).toEqual([{ action: 'boss.archive' }, { action: 'boss.restore' }]);
  expect(await env.DB.prepare("SELECT action FROM audit_log WHERE id = 'archive-prior-audit'").first()).toEqual({ action: 'boss.create' });
});

it('returns 404 for unknown targets and 409 restoring a live boss', async () => {
  expect((await post('missing', 'archive')).status).toBe(404);
  expect((await post('missing', 'restore')).status).toBe(404);
  expect((await post(manager, 'restore')).status).toBe(409);
});

it('requires admin boss authentication for both operations', async () => {
  for (const action of ['archive', 'restore']) {
    expect((await post(manager, action, MANAGER)).status).toBe(403);
    expect((await post(manager, action, 'archive-viewer-token')).status).toBe(403);
    const response = await SELF.fetch(`https://test.local/api/bosses/${manager}/${action}`, { method: 'POST', headers: authHeaders() });
    expect(response.status).toBe(401);
    expect((await post(manager, action, 'invalid')).status).toBe(401);
  }
});

it('protects the last live admin and prevents self archive even with another admin', async () => {
  const last = await post(admin, 'archive');
  expect(last.status).toBe(400);
  expect(await last.text()).toContain('last unarchived admin');
  const other = await seedBossToken('Other admin', 'admin', 'archive-other-admin');
  const self = await post(admin, 'archive');
  expect(self.status).toBe(400);
  expect(await self.text()).toContain('self');
  expect((await post(other, 'archive')).status).toBe(200);
  expect((await post(admin, 'archive')).status).toBe(400);
});

it('blocks archived target mutations, including grants, token rotation, and external accounts', async () => {
  expect((await post(manager, 'archive')).status).toBe(200);
  for (const [method, path, body] of [
    ['PATCH', '', { name: 'Changed' }], ['PATCH', '', { preferences: {} }],
    ['POST', '/access', { agent_id: 'test-agent-id' }], ['DELETE', '/access/test-agent-id', undefined],
    ['POST', '/token', undefined], ['POST', '/external-accounts', { provider: 'telegram', provider_user_id: '123' }],
    ['DELETE', '/external-accounts/missing', undefined],
  ] as const) {
    const response = await SELF.fetch(`https://test.local/api/bosses/${manager}${path}`, { method, headers: headers(), body: body && JSON.stringify(body) });
    expect(response.status, `${method} ${path}`).toBe(409);
    expect(await response.text()).toContain('boss is archived');
  }
  expect((await post(manager, 'restore')).status).toBe(200);
});
