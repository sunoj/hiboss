// Exercises first-install authorization through real Worker HTTP requests.
// Covers stored bootstrap grants, boss administration, and last-admin survival.
import { testRequest, testJson } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import { getTestAgentId, mintTestInvite, seedBossToken, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Install admin', 'admin', 'install-admin', 'install-admin');
});

beforeEach(async () => {
  await env.DB.prepare("UPDATE bosses SET role = 'admin' WHERE id = 'install-admin'").run();
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name) VALUES (?, ?)')
    .bind(getTestAgentId(), 'test-agent').run();
  await env.DB.prepare('INSERT OR IGNORE INTO agent_keys (agent_id, key_hash, label) VALUES (?, ?, ?)')
    .bind(getTestAgentId(), await hashApiKey('hb_test_key_0000000000000000'), 'install-test').run();
});

function write(path: string, body: unknown, method = 'PATCH', token = 'install-admin') {
  return SELF.fetch(`https://test.local/api/${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
}

it('rule 3 grants every bootstrap profile admin only after approval', async () => {
  await env.DB.prepare('DELETE FROM channel_configs').run();
  await env.DB.prepare('DELETE FROM boss_agent_access').run();
  await env.DB.prepare('DELETE FROM api_keys').run();
  env.BOOTSTRAP_SECRET = 'synthetic-install-secret';
  const response = await testRequest('POST', 'https://test.local/api/join', {
      'Content-Type': 'application/json', 'X-Bootstrap-Secret': 'synthetic-install-secret',
    }, { device: { label: 'install' }, profiles: [
      { profile: 'aid', name: 'install-aid' }, { profile: 'codex', name: 'install-codex' },
    ] });
  expect(response.status).toBe(201);
  expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM api_keys').first('n')).toBe(0);
  const pending = await response.json() as { request_id: string };
  await env.DB.prepare("INSERT INTO api_keys (id, name) VALUES ('intervening', 'intervening')").run();
  const approved = await write(`boss/join-requests/${pending.request_id}/approve`, {}, 'POST');
  expect(approved.status).toBe(200);
  const rows = await env.DB.prepare("SELECT is_admin FROM api_keys WHERE name LIKE 'install-%'")
    .all<{ is_admin: number }>();
  expect(rows.results).toEqual([{ is_admin: 1 }, { is_admin: 1 }]);
  expect(await env.DB.prepare("SELECT is_admin FROM api_keys WHERE id = 'intervening'")
    .first('is_admin')).toBe(0);
});

it('rule 3 keeps invited profiles ordinary even with a forged bootstrap admin field', async () => {
  const pending = await testJson(201, testRequest('POST', 'https://test.local/api/join',
    { 'Content-Type': 'application/json' }, { device: { label: 'invited' }, invite: await mintTestInvite(),
      profiles: [{ profile: 'aid', name: 'invited-aid' }], bootstrap_admin: 1 })) as { request_id: string };
  expect((await write(`boss/join-requests/${pending.request_id}/approve`, {}, 'POST')).status).toBe(200);
  expect(await env.DB.prepare("SELECT is_admin FROM api_keys WHERE name = 'invited-aid'")
    .first('is_admin')).toBe(0);
});

it('rule 4 lets an admin boss grant and revoke agent admin with an audit record', async () => {
  for (const admin of [true, false]) {
    const response = await write(`boss/agents/${getTestAgentId()}/config`, { admin });
    expect(response.status).toBe(200);
    expect(await env.DB.prepare('SELECT is_admin FROM api_keys WHERE id = ?')
      .bind(getTestAgentId()).first('is_admin')).toBe(Number(admin));
  }
  const rows = await env.DB.prepare("SELECT id FROM audit_log WHERE action = 'agent.admin'").all();
  expect(rows.results).toHaveLength(2);
});

it.each(['manager', 'viewer'])('rule 4 refuses admin changes from a %s', async role => {
  await seedBossToken('Other', role, `install-${role}`, `install-${role}`);
  const response = await write(`boss/agents/${getTestAgentId()}/config`, { admin: true },
    'PATCH', `install-${role}`);
  expect([403, 404]).toContain(response.status);
});

it.each(['PATCH', 'DELETE'])('rule 5 refuses removing the last live admin with %s', async method => {
  await env.DB.prepare("UPDATE bosses SET role = 'viewer' WHERE id != 'install-admin'").run();
  await seedBossToken('Archived admin', 'admin', `archived-${method}`, `archived-${method}`);
  await env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?")
    .bind(`archived-${method}`).run();
  const response = await write('bosses/install-admin', { role: 'viewer' }, method);
  expect(response.status).toBe(409);
  expect(await env.DB.prepare("SELECT role FROM bosses WHERE id = 'install-admin'").first('role'))
    .toBe('admin');
});

it('rule 5 allows removing one of two live admins', async () => {
  await seedBossToken('Spare admin', 'admin', 'install-spare', 'install-spare');
  expect((await write('bosses/install-spare', { role: 'manager' })).status).toBe(200);
  expect((await write('bosses/install-spare', {}, 'DELETE')).status).toBe(200);
});
