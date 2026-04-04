// Tests for quiet-hours helpers and delivery deferral integration.
// Covers timezone-aware scheduling plus queued vs immediate delivery behavior.
// Depends on cloudflare:test, seeded D1 fixtures, and quiet-hours helpers.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { getAgentQuietHoursEnd, getQuietHoursEnd, isInQuietHours } from './quiet-hours';

beforeAll(async () => {
  await seedDatabase();
});

describe('isInQuietHours', () => {
  it('returns false when quiet hours are incomplete', () => {
    expect(isInQuietHours(null, '08:00', 'Asia/Bangkok')).toBe(false);
    expect(isInQuietHours('22:00', null, 'Asia/Bangkok')).toBe(false);
  });

  it('handles overnight quiet hours', () => {
    const inside = new Date('2026-04-04T16:30:00.000Z');
    const outside = new Date('2026-04-04T03:30:00.000Z');
    expect(isInQuietHours('22:00', '08:00', 'Asia/Bangkok', inside)).toBe(true);
    expect(isInQuietHours('22:00', '08:00', 'Asia/Bangkok', outside)).toBe(false);
  });

  it('handles same-day quiet hours', () => {
    const inside = new Date('2026-04-04T06:30:00.000Z');
    const outside = new Date('2026-04-04T10:30:00.000Z');
    expect(isInQuietHours('13:00', '17:00', 'Asia/Bangkok', inside)).toBe(true);
    expect(isInQuietHours('13:00', '17:00', 'Asia/Bangkok', outside)).toBe(false);
  });
});

describe('getQuietHoursEnd', () => {
  it('returns the same local-day end when it is still upcoming', () => {
    const now = new Date('2026-04-04T00:30:00.000Z');
    expect(getQuietHoursEnd('08:00', 'Asia/Bangkok', now).toISOString()).toBe('2026-04-04T01:00:00.000Z');
  });

  it('returns the next local-day end when today has already passed', () => {
    const now = new Date('2026-04-04T16:30:00.000Z');
    expect(getQuietHoursEnd('08:00', 'Asia/Bangkok', now).toISOString()).toBe('2026-04-05T01:00:00.000Z');
  });
});

describe('getAgentQuietHoursEnd', () => {
  it('resolves quiet-hours end timestamps for UTC, Asia/Bangkok, and America/New_York', async () => {
    await seedQuietHoursBoss('quiet-hours-utc', 'UTC', '22:00', '08:00');
    await seedQuietHoursBoss('quiet-hours-bkk', 'Asia/Bangkok', '22:00', '08:00');
    await seedQuietHoursBoss('quiet-hours-nyc', 'America/New_York', '19:00', '21:00');

    const now = new Date('2026-04-04T23:30:00.000Z');
    expect((await getAgentQuietHoursEnd(env, 'quiet-hours-utc', now))?.toISOString()).toBe('2026-04-05T08:00:00.000Z');
    expect((await getAgentQuietHoursEnd(env, 'quiet-hours-bkk', now))?.toISOString()).toBe('2026-04-05T01:00:00.000Z');
    expect((await getAgentQuietHoursEnd(env, 'quiet-hours-nyc', now))?.toISOString()).toBe('2026-04-05T01:00:00.000Z');
  });

  it('returns the next-morning delivery time for overnight quiet hours', async () => {
    await seedQuietHoursBoss('quiet-hours-overnight', 'America/New_York', '22:00', '08:00');

    const end = await getAgentQuietHoursEnd(env, 'quiet-hours-overnight', new Date('2026-04-05T03:30:00.000Z'));
    expect(end?.toISOString()).toBe('2026-04-05T12:00:00.000Z');
  });
});

describe('quiet-hours delivery integration', () => {
  it('queues a normal-priority message during quiet hours', async () => {
    const headers = await createQuietHoursAgent('quiet-hours-route-normal', 'hb_quiet_hours_normal_key_0000');

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers,
      body: JSON.stringify({ body: 'quiet-hours:queue-me' }),
    });
    const created = await res.json() as { id: string };

    expect(res.status).toBe(201);
    const queueRow = await env.DB
      .prepare('SELECT channel, status, scheduled_at FROM delivery_queue WHERE message_id = ?')
      .bind(created.id)
      .first<{ channel: string; status: string; scheduled_at: string }>();
    expect(queueRow?.channel).toBe('api');
    expect(queueRow?.status).toBe('pending');
    expect(new Date(queueRow!.scheduled_at).getTime()).toBeGreaterThan(Date.now());
  });

  it('delivers a critical message immediately during quiet hours', async () => {
    const headers = await createQuietHoursAgent('quiet-hours-route-critical', 'hb_quiet_hours_critical_key_00');

    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers,
      body: JSON.stringify({ body: 'quiet-hours:deliver-now', priority: 'critical' }),
    });
    const created = await res.json() as { id: string };

    expect(res.status).toBe(201);
    const queueCount = await env.DB
      .prepare('SELECT COUNT(*) AS total FROM delivery_queue WHERE message_id = ?')
      .bind(created.id)
      .first<{ total: number }>();
    const message = await env.DB
      .prepare('SELECT status FROM messages WHERE id = ?')
      .bind(created.id)
      .first<{ status: string }>();
    expect(queueCount?.total).toBe(0);
    expect(message?.status).toBe('delivered');
  });
});

async function createQuietHoursAgent(agentId: string, apiKey: string): Promise<Record<string, string>> {
  const keyHash = await hashApiKey(apiKey);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, ?, ?, 1)'
  ).bind(`cfg-${agentId}`, agentId, 'api', JSON.stringify({})).run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)'
  ).bind(
    `boss-${agentId}`,
    `Boss ${agentId}`,
    'manager',
    JSON.stringify({
      quiet_hours_start: toUtcTime(-1),
      quiet_hours_end: toUtcTime(1),
      timezone: 'UTC',
    }),
  ).run();
  await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(`boss-${agentId}`, agentId)
    .run();
  return {
    Authorization: `Bearer ${apiKey}`,
    'Content-Type': 'application/json',
  };
}

async function seedQuietHoursBoss(agentId: string, timezone: string, start: string, end: string): Promise<void> {
  const keyHash = await hashApiKey(`${agentId}-key`);
  await env.DB.prepare('INSERT OR REPLACE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)'
  ).bind(
    `boss-${agentId}`,
    `Boss ${agentId}`,
    'manager',
    JSON.stringify({ quiet_hours: { start, end }, timezone }),
  ).run();
  await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(`boss-${agentId}`, agentId)
    .run();
}

function toUtcTime(offsetMinutes: number): string {
  const now = new Date(Date.now() + offsetMinutes * 60_000);
  return now.toISOString().slice(11, 16);
}
