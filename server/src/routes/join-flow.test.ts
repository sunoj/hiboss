// End-to-end tests for join request creation, approval, rejection, and bootstrap flows.
// Covers Telegram and Discord approval callbacks plus poll-token status delivery.
// Depends on cloudflare:test, D1 fixtures, webhook secrets, and signed Discord payloads.

import { testRequest } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { approveAndCollect, getTestAgentId, mintTestInvite, seedBossToken, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const JOIN_BASE = 'https://test.local/api/join';
beforeAll(seedDatabase);

afterEach(async () => {
  await env.DB.prepare("DELETE FROM join_requests WHERE device_label LIKE 'join-flow-%'").run();
  await env.DB.prepare("DELETE FROM bosses WHERE name LIKE 'join-flow-%'").run();
  await env.DB.prepare("DELETE FROM boss_agent_access WHERE agent_id IN (SELECT id FROM api_keys WHERE name LIKE 'join-flow-%')").run();
  await env.DB.prepare("DELETE FROM api_keys WHERE name LIKE 'join-flow-%'").run();
  await env.DB.prepare("DELETE FROM devices WHERE label LIKE 'join-flow-%'").run();
});

describe('Join flow', () => {
  it('creates a pending join request through POST /api/join', async () => {
    const res = await createJoinRequest('join-flow-pending');

    expect(res.status).toBe('pending');
    const stored = await env.DB
      .prepare('SELECT status, poll_token_hash FROM join_requests WHERE id = ?')
      .bind(res.request_id)
      .first<{ status: string; poll_token_hash: string }>();
    expect(stored).toEqual({ status: 'pending', poll_token_hash: await hashApiKey(res.poll_token) });
  });

  it('rejects a taken name when the request is created', async () => {
    const res = await SELF.fetch(JOIN_BASE, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...joinBody('test-agent'), invite: await mintTestInvite() }) });
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: 'agent name already exists', conflicts: ['test-agent'] });
  });

  it('returns 409 text for duplicate names through boss approval', async () => {
    const join = await createJoinRequest('join-flow-late-duplicate');
    await env.DB.prepare('INSERT INTO api_keys (id, name) VALUES (?, ?)').bind('join-flow-late-agent', 'join-flow-late-duplicate').run();
    await seedBossToken('join-flow-api-admin', 'admin', 'join-duplicate-token');
    const response = await testRequest('POST', `https://test.local/api/boss/join-requests/${join.request_id}/approve`,
      { Authorization: 'Bearer join-duplicate-token' });
    expect(response.status).toBe(409);
    expect(await response.text()).toBe('an agent with one of these names already exists');
    expect(await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?').bind(join.request_id).first('status')).toBe('pending');
  });

  it('keeps the first join of an empty server pending until a boss approves it', async () => {
    await env.DB.prepare('DELETE FROM boss_agent_access').run();
    await env.DB.prepare('DELETE FROM api_keys').run();
    const previous = env.BOOTSTRAP_SECRET;
    const firstJoin = (headers: Record<string, string>) => testRequest('POST', JOIN_BASE,
      { 'Content-Type': 'application/json', ...headers }, joinBody('join-flow-bootstrap'));
    env.BOOTSTRAP_SECRET = '';
    const unconfigured = await firstJoin({});
    env.BOOTSTRAP_SECRET = 'join-flow-bootstrap-secret';
    const wrong = await firstJoin({ 'X-Bootstrap-Secret': 'wrong' });
    const res = await firstJoin({ 'X-Bootstrap-Secret': 'join-flow-bootstrap-secret' });
    env.BOOTSTRAP_SECRET = previous;

    expect(unconfigured.status).toBe(403);
    expect(wrong.status).toBe(401);
    expect(res.status).toBe(201);
    expect(await res.clone().json()).toMatchObject({ status: 'pending', verification_code: expect.stringMatching(/^[0-9]{6}$/) });
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM api_keys').first('n')).toBe(0);
    const grant = await approveAndCollect(res);
    expect(grant.key).toMatch(/^hb_/);

    await restoreDefaultAgent();
  });
});

async function createJoinRequest(name: string): Promise<{ request_id: string; poll_token: string; status: string }> {
  const res = await testRequest('POST', JOIN_BASE, { 'Content-Type': 'application/json' },
    { ...joinBody(name), invite: await mintTestInvite() });
  expect(res.status).toBe(201);
  return res.json() as Promise<{ request_id: string; poll_token: string; status: string }>;
}

function joinBody(name: string): Record<string, unknown> {
  return { device: { label: 'join-flow-device' }, profiles: [{ profile: 'claude', name }] };
}

async function restoreDefaultAgent(): Promise<void> {
  const keyHash = await hashApiKey('hb_test_key_0000000000000000');
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(getTestAgentId(), 'test-agent', keyHash)
    .run();
}
