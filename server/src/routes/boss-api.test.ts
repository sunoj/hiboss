// Tests for /api/boss/* endpoints: boss-authenticated profile, preferences, messages, sessions.
// Covers boss auth flow, message listing with search, and reply.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import type { MessageRow } from '../types';
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { seedDatabase, getTestAgentId, authHeaders, seedBossToken } from '../test-helpers';

const BOSS_TOKEN = `hb_boss_${"ab".repeat(16)}`;
let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  // Create boss with token
  bossId = await seedBossToken('API Boss', 'admin', BOSS_TOKEN);
  // Grant access to test agent
  await env.DB
    .prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, getTestAgentId())
    .run();
  // Seed messages from test agent
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'normal')"
  ).bind('boss-api-msg-1', getTestAgentId(), 'Hello from agent').run();
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'api', ?, 'sent', 'high')"
  ).bind('boss-api-msg-2', getTestAgentId(), 'Deploy completed successfully').run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO agent_groups (id, name, description, owner_id) VALUES (?, ?, ?, ?)'
  ).bind('boss-api-group-1', 'Boss API Group', 'Visible to boss token', getTestAgentId()).run();
  await env.DB.prepare(
    "INSERT OR REPLACE INTO routing_rules (id, owner_id, channel, pattern, target_agent_id, priority, enabled) VALUES (?, ?, 'telegram', ?, ?, 10, 1)"
  ).bind('boss-api-rule-1', getTestAgentId(), 'deploy', getTestAgentId()).run();
  await env.DB.prepare(
    "INSERT OR REPLACE INTO audit_log (id, actor_type, actor_id, action, resource_type, resource_id, details) VALUES (?, 'agent', ?, ?, 'message', ?, ?)"
  ).bind('boss-api-audit-1', getTestAgentId(), 'boss.contract.read', 'boss-api-msg-1', 'seeded audit row').run();
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' };
}

describe('Boss auth', () => {
  it('rejects invalid token', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me', {
      headers: { Authorization: 'Bearer hb_boss_invalid', 'Content-Type': 'application/json' },
    });
    expect(res.status).toBe(401);
  });

  it('rejects agent key on boss endpoint', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me', {
      headers: { Authorization: 'Bearer hb_test_key_0000000000000000', 'Content-Type': 'application/json' },
    });
    expect(res.status).toBe(401);
  });
});

describe('GET /api/boss/me', () => {
  it('returns boss profile', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { id: string; name: string; role: string; agent_ids: string[] };
    expect(data.id).toBe(bossId);
    expect(data.name).toBe('API Boss');
    expect(data.role).toBe('admin');
    expect(data.agent_ids).toBeInstanceOf(Array);
  });
});

describe('Boss preferences', () => {
  it('GET /api/boss/me/preferences returns empty by default', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/me/preferences', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as Record<string, unknown>;
    expect(data).toEqual({});
  });

  it('PUT /api/boss/me/preferences sets and merges', async () => {
    // Set initial
    const res1 = await SELF.fetch('http://localhost/api/boss/me/preferences', {
      method: 'PUT',
      headers: bossHeaders(),
      body: JSON.stringify({ timezone: 'UTC' }),
    });
    expect(res1.status).toBe(200);
    const data1 = await res1.json() as { timezone: string };
    expect(data1.timezone).toBe('UTC');
    // Merge more
    const res2 = await SELF.fetch('http://localhost/api/boss/me/preferences', {
      method: 'PUT',
      headers: bossHeaders(),
      body: JSON.stringify({ quiet_hours: { start: '22:00', end: '08:00' } }),
    });
    expect(res2.status).toBe(200);
    const data2 = await res2.json() as { timezone: string; quiet_hours: { start: string; end: string } };
    expect(data2.timezone).toBe('UTC');
    expect(data2.quiet_hours).toEqual({ start: '22:00', end: '08:00' });
  });
});

describe('GET /api/boss/agents', () => {
  it('returns accessible agents', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/agents', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { agents: { name: string }[] };
    expect(data.agents).toBeInstanceOf(Array);
    // Admin sees all agents, should include test-agent
    const names = data.agents.map((a) => a.name);
    expect(names).toContain('test-agent');
  });
});

describe('GET /api/boss/groups', () => {
  it('lists groups for accessible agents', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/groups', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { groups: { id: string }[] };
    expect(data.groups).toBeInstanceOf(Array);
    expect(data.groups.some((group) => group.id === 'boss-api-group-1')).toBe(true);
  });
});

describe('GET /api/boss/routing-rules', () => {
  it('lists routing rules for accessible agents', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/routing-rules', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { rules: { id: string }[] };
    expect(data.rules).toBeInstanceOf(Array);
    expect(data.rules.some((rule) => rule.id === 'boss-api-rule-1')).toBe(true);
  });
});

describe('GET /api/boss/audit', () => {
  it('lists audit entries for accessible agents', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/audit?limit=10', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { entries: { id: string }[] };
    expect(data.entries).toBeInstanceOf(Array);
    expect(data.entries.some((entry) => entry.id === 'boss-api-audit-1')).toBe(true);
  });
});

describe('GET /api/boss/messages', () => {
  it('lists agent messages', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: MessageRow[]; total: number };
    expect(data.messages).toBeInstanceOf(Array);
    expect(data.total).toBeGreaterThanOrEqual(2);
  });

  it('filters by unread', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?unread=true', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: MessageRow[]; total: number };
    for (const m of data.messages) {
      expect(['sent', 'delivered']).toContain(m.status);
    }
  });

  it('filters by priority', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?priority=high', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: MessageRow[]; total: number };
    for (const m of data.messages) {
      expect(m.priority).toBe('high');
    }
  });

  it('supports search filter', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?search=Deploy', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: MessageRow[]; total: number };
    expect(data.messages.length).toBeGreaterThanOrEqual(1);
    for (const m of data.messages) {
      expect(m.body.toLowerCase()).toContain('deploy');
    }
  });

});

describe('GET /api/boss/messages', () => {
  it('search returns empty for no match', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?search=xyznonexistent', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: MessageRow[]; total: number };
    expect(data.messages.length).toBe(0);
  });

  it('supports limit and offset', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages?limit=1&offset=0', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: MessageRow[]; total: number };
    expect(data.messages.length).toBeLessThanOrEqual(1);
  });

  it('filters by agent', async () => {
    const res = await SELF.fetch(`http://localhost/api/boss/messages?agent=${getTestAgentId()}`, { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: MessageRow[]; total: number };
    expect(data.messages.length).toBeGreaterThanOrEqual(1);
  });
});

describe('GET /api/boss/messages/:id', () => {
  it('returns message with replies', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/boss-api-msg-1', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { id: string; replies: MessageRow[] };
    expect(data.id).toBe('boss-api-msg-1');
    expect(data.replies).toBeInstanceOf(Array);
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/messages/nonexistent', { headers: bossHeaders() });
    expect(res.status).toBe(404);
  });
});
