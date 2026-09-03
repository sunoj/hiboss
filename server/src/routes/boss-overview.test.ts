// Tests for GET /api/boss/overview — dashboard aggregate.
// Verifies KPIs, priority distribution, session status counts, and channel health,
// scoped to the boss's accessible agents.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const BOSS_TOKEN = 'hb_boss_overview_00112233445566778899aabb';
const AGENT_ID = 'overview-agent-1';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(
    "INSERT INTO api_keys (id, name, key_hash) VALUES (?, 'overview-agent', ?)",
  ).bind(AGENT_ID, await hashApiKey('hb_overview_agent_key')).run();

  const bossId = await seedBossToken('Overview Boss', 'viewer', BOSS_TOKEN);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, AGENT_ID).run();

  // Two pending option decisions (one blocking), one plain unread, priorities vary.
  const soon = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  await env.DB.prepare(
    `INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at)
     VALUES (?, ?, 'agent_to_boss', 'blocking', 'discord', 'Approve migration?', 'delivered', 'critical', ?, ?)`,
  ).bind('ov-crit', AGENT_ID, JSON.stringify({ options: ['Approve', 'Reject'] }), soon).run();
  await env.DB.prepare(
    `INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata)
     VALUES (?, ?, 'agent_to_boss', 'async', 'telegram', 'Pick a strategy', 'sent', 'high', ?)`,
  ).bind('ov-high', AGENT_ID, JSON.stringify({ options: ['A', 'B', 'C'] })).run();
  await env.DB.prepare(
    `INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority)
     VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'Progress update', 'sent', 'normal')`,
  ).bind('ov-normal', AGENT_ID).run();

  // A working session and a completed session.
  await env.DB.prepare(
    "INSERT INTO sessions (id, agent_id, label, status, status_text) VALUES (?, ?, 'sess-a', 'working', 'building')",
  ).bind('ov-sess-work', AGENT_ID).run();
  await env.DB.prepare(
    "INSERT INTO sessions (id, agent_id, label, status, status_text) VALUES (?, ?, 'sess-b', 'completed', 'done')",
  ).bind('ov-sess-done', AGENT_ID).run();

  // A configured discord channel for health.
  await env.DB.prepare(
    "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'discord', '{}', 1)",
  ).bind(AGENT_ID).run();
});

function bossHeaders(): Record<string, string> {
  return { Authorization: `Bearer ${BOSS_TOKEN}`, 'Content-Type': 'application/json' };
}

describe('GET /api/boss/overview', () => {
  it('returns KPIs scoped to accessible agents', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/overview', { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const body = await res.json() as {
      kpis: Record<string, number>;
      priorityDistribution: Record<string, number>;
      sessionStatus: Record<string, number>;
      channels: { channel: string; configured: boolean }[];
    };
    expect(body.kpis.pendingDecisions).toBe(2);
    expect(body.kpis.blockingPending).toBe(1);
    expect(body.kpis.workingSessions).toBe(1);
    expect(body.kpis.unread1h).toBeGreaterThanOrEqual(2);
  });

  it('aggregates priority distribution and session status', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/overview', { headers: bossHeaders() });
    const body = await res.json() as {
      priorityDistribution: Record<string, number>;
      sessionStatus: Record<string, number>;
      channels: { channel: string; configured: boolean }[];
    };
    expect(body.priorityDistribution.critical).toBe(1);
    expect(body.priorityDistribution.high).toBe(1);
    expect(body.priorityDistribution.normal).toBe(1);
    expect(body.sessionStatus.working).toBe(1);
    expect(body.sessionStatus.completed).toBe(1);
    const discord = body.channels.find((ch) => ch.channel === 'discord');
    const api = body.channels.find((ch) => ch.channel === 'api');
    expect(discord?.configured).toBe(true);
    expect(api?.configured).toBe(true);
  });
});
