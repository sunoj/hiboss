// Integration tests for boss-scoped write contract and console read endpoints.
// Covers groups, agent config, and system doctor.
// Depends on cloudflare:test env, shared test helpers, and boss token auth.

import { testRequest, testJson } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { getTestAgentId, seedDatabase } from '../test-helpers';

const ADMIN_TOKEN = 'hb_boss_writes_admin_0011223344556677';
const MANAGER_TOKEN = 'hb_boss_writes_manager_0011223344556677';
const VIEWER_TOKEN = 'hb_boss_writes_viewer_0011223344556677';
const OTHER_AGENT_ID = 'boss-writes-other-agent';
let groupId = '';

beforeAll(async () => {
  await seedDatabase();
  await seedAgent(OTHER_AGENT_ID);
  await seedBoss('boss-writes-admin', 'Boss Writes Admin', 'admin', ADMIN_TOKEN);
  await seedBoss('boss-writes-manager', 'Boss Writes Manager', 'manager', MANAGER_TOKEN);
  await seedBoss('boss-writes-viewer', 'Boss Writes Viewer', 'viewer', VIEWER_TOKEN);
  await grantAccess('boss-writes-manager', getTestAgentId());
  await grantAccess('boss-writes-viewer', getTestAgentId());
});

function bossHeaders(token = ADMIN_TOKEN): Record<string, string> {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

describe('boss write contract', () => {
  it('creates a group for an accessible owner', async () => {
    const data = await testJson(201,
      testRequest('POST', 'https://test.local/api/boss/groups', bossHeaders(), {
          name: `boss-writes-group-${Date.now()}`,
          description: 'created by boss write tests',
          owner_agent_id: getTestAgentId(),
        })) as { id: string; owner_id: string };
    expect(data.owner_id).toBe(getTestAgentId());
    groupId = data.id;
  });

  it('adds a member and broadcasts to the group', async () => {
    const add = await testRequest('POST', `https://test.local/api/boss/groups/${groupId}/members`,
      bossHeaders(), { agent_id: getTestAgentId() });
    expect(add.status).toBe(201);

    const broadcast = await testRequest('POST', `https://test.local/api/boss/groups/${groupId}/broadcast`,
      bossHeaders(), { body: 'Boss write broadcast', priority: 'high' });
    expect(broadcast.status).toBe(201);
    const data = await broadcast.json() as { count: number; messages: { agent_id: string }[] };
    expect(data.count).toBe(1);
    expect(data.messages[0]?.agent_id).toBe(getTestAgentId());
  });

  it('updates agent config through boss scope', async () => {
    const res = await testRequest('PATCH', `https://test.local/api/boss/agents/${getTestAgentId()}/config`,
      bossHeaders(),
      { default_priority: 'critical', rate_limit: 11 });
    expect(res.status).toBe(200);
    const data = await res.json() as { default_priority: string; rate_limit: number };
    expect(data.default_priority).toBe('critical');
    expect(data.rate_limit).toBe(11);
  });

  it('returns a cheap system doctor snapshot', async () => {
    const res = await SELF.fetch('https://test.local/api/boss/system', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { db_ok: boolean; server_time: string };
    expect(data.db_ok).toBe(true);
    expect(typeof data.server_time).toBe('string');
  });

  it('rejects viewer writes and non-accessible manager writes', async () => {
    const viewer = await testRequest('POST', 'https://test.local/api/boss/groups', bossHeaders(VIEWER_TOKEN),
      { name: `viewer-denied-${Date.now()}`, owner_agent_id: getTestAgentId() });
    expect(viewer.status).toBe(403);

    const manager = await testRequest('POST', 'https://test.local/api/boss/groups',
      bossHeaders(MANAGER_TOKEN), { name: `manager-denied-${Date.now()}`, owner_agent_id: OTHER_AGENT_ID });
    expect(manager.status).toBe(403);
  });


  it('deletes a boss-created group', async () => {
    const response = await testRequest('DELETE', `https://test.local/api/boss/groups/${groupId}`, bossHeaders());
    expect(response.status).toBe(200);
  });
});

async function seedAgent(id: string): Promise<void> {
  const tokenHash = await hashApiKey(`${id}_token`);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(id, id, tokenHash)
    .run();
}

async function seedBoss(id: string, name: string, role: string, token: string): Promise<void> {
  const tokenHash = await hashApiKey(token);
  await env.DB.prepare('INSERT OR IGNORE INTO bosses (id, name, role) VALUES (?, ?, ?)')
    .bind(id, name, role)
    .run();
  await env.DB.prepare('INSERT OR IGNORE INTO boss_tokens (boss_id, label, token_hash) VALUES (?, ?, ?)')
    .bind(id, 'test', tokenHash).run();
}

async function grantAccess(bossId: string, agentId: string): Promise<void> {
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agentId)
    .run();
}
