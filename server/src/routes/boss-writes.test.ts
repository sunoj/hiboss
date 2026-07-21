// Integration tests for boss-scoped write contract and console read endpoints.
// Covers groups, routing rules, agent config, channel projection, and system doctor.
// Depends on cloudflare:test env, shared test helpers, and boss token auth.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { getTestAgentId, seedDatabase } from '../test-helpers';

const ADMIN_TOKEN = 'hb_boss_writes_admin_0011223344556677';
const MANAGER_TOKEN = 'hb_boss_writes_manager_0011223344556677';
const VIEWER_TOKEN = 'hb_boss_writes_viewer_0011223344556677';
const OTHER_AGENT_ID = 'boss-writes-other-agent';
let groupId = '';
let ruleId = '';

beforeAll(async () => {
  await seedDatabase();
  await seedAgent(OTHER_AGENT_ID);
  await seedBoss('boss-writes-admin', 'Boss Writes Admin', 'admin', ADMIN_TOKEN);
  await seedBoss('boss-writes-manager', 'Boss Writes Manager', 'manager', MANAGER_TOKEN);
  await seedBoss('boss-writes-viewer', 'Boss Writes Viewer', 'viewer', VIEWER_TOKEN);
  await grantAccess('boss-writes-manager', getTestAgentId());
  await grantAccess('boss-writes-viewer', getTestAgentId());
  await env.DB.prepare(
    "INSERT INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, 'email', ?, 1) ON CONFLICT(agent_id, channel) DO UPDATE SET config = excluded.config, enabled = 1"
  ).bind(
    'boss-writes-email-config',
    getTestAgentId(),
    JSON.stringify({ label: 'Ops inbox', webhook_url: 'https://secret.test/hook', bot_token: 'secret-token' }),
  ).run();
});

function bossHeaders(token = ADMIN_TOKEN): Record<string, string> {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

describe('boss write contract', () => {
  it('creates a group for an accessible owner', async () => {
    const res = await SELF.fetch('https://test.local/api/boss/groups', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({
        name: `boss-writes-group-${Date.now()}`,
        description: 'created by boss write tests',
        owner_agent_id: getTestAgentId(),
      }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { id: string; owner_id: string };
    expect(data.owner_id).toBe(getTestAgentId());
    groupId = data.id;
  });

  it('adds a member and broadcasts to the group', async () => {
    const add = await SELF.fetch(`https://test.local/api/boss/groups/${groupId}/members`, {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ agent_id: getTestAgentId() }),
    });
    expect(add.status).toBe(201);

    const broadcast = await SELF.fetch(`https://test.local/api/boss/groups/${groupId}/broadcast`, {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({ body: 'Boss write broadcast', priority: 'high' }),
    });
    expect(broadcast.status).toBe(201);
    const data = await broadcast.json() as { count: number; messages: { agent_id: string }[] };
    expect(data.count).toBe(1);
    expect(data.messages[0]?.agent_id).toBe(getTestAgentId());
  });

  it('creates a routing rule for accessible owner and target agents', async () => {
    const res = await SELF.fetch('https://test.local/api/boss/routing-rules', {
      method: 'POST',
      headers: bossHeaders(),
      body: JSON.stringify({
        owner_agent_id: getTestAgentId(),
        channel: 'telegram',
        pattern: 'boss-write.*',
        target_agent_id: getTestAgentId(),
        priority: 7,
      }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as { id: string; owner_id: string; priority: number };
    expect(data.owner_id).toBe(getTestAgentId());
    expect(data.priority).toBe(7);
    ruleId = data.id;
  });

  it('updates agent config through boss scope', async () => {
    const res = await SELF.fetch(`https://test.local/api/boss/agents/${getTestAgentId()}/config`, {
      method: 'PATCH',
      headers: bossHeaders(),
      body: JSON.stringify({ default_priority: 'critical', rate_limit: 11, channel_routing: { alerts: 'email' } }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { default_priority: string; rate_limit: number; channel_routing: { alerts: string } };
    expect(data.default_priority).toBe('critical');
    expect(data.rate_limit).toBe(11);
    expect(data.channel_routing.alerts).toBe('email');
  });

  it('returns channel rows without secret config fields', async () => {
    const res = await SELF.fetch('https://test.local/api/boss/channels', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { agent_id: string; label?: string; bot_token?: string; webhook_url?: string }[];
    const row = data.find((item) => item.agent_id === getTestAgentId() && item.label === 'Ops inbox');
    expect(row).toBeDefined();
    expect(row?.bot_token).toBeUndefined();
    expect(row?.webhook_url).toBeUndefined();
  });

  it('returns a cheap system doctor snapshot', async () => {
    const res = await SELF.fetch('https://test.local/api/boss/system', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { db_ok: boolean; server_time: string; channels: unknown[] };
    expect(data.db_ok).toBe(true);
    expect(typeof data.server_time).toBe('string');
    expect(Array.isArray(data.channels)).toBe(true);
  });

  it('rejects viewer writes and non-accessible manager writes', async () => {
    const viewer = await SELF.fetch('https://test.local/api/boss/groups', {
      method: 'POST',
      headers: bossHeaders(VIEWER_TOKEN),
      body: JSON.stringify({ name: `viewer-denied-${Date.now()}`, owner_agent_id: getTestAgentId() }),
    });
    expect(viewer.status).toBe(403);

    const manager = await SELF.fetch('https://test.local/api/boss/groups', {
      method: 'POST',
      headers: bossHeaders(MANAGER_TOKEN),
      body: JSON.stringify({ name: `manager-denied-${Date.now()}`, owner_agent_id: OTHER_AGENT_ID }),
    });
    expect(manager.status).toBe(403);
  });

  it('deletes boss-created routing rule and group', async () => {
    const deleteRule = await SELF.fetch(`https://test.local/api/boss/routing-rules/${ruleId}`, {
      method: 'DELETE',
      headers: bossHeaders(),
    });
    expect(deleteRule.status).toBe(200);

    const deleteGroup = await SELF.fetch(`https://test.local/api/boss/groups/${groupId}`, {
      method: 'DELETE',
      headers: bossHeaders(),
    });
    expect(deleteGroup.status).toBe(200);
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
  await env.DB.prepare('INSERT OR IGNORE INTO bosses (id, name, role, token_hash) VALUES (?, ?, ?, ?)')
    .bind(id, name, role, tokenHash)
    .run();
}

async function grantAccess(bossId: string, agentId: string): Promise<void> {
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agentId)
    .run();
}
