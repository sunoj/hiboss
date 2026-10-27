// Tests for quiet-hours helpers and delivery deferral integration.
// Covers timezone-aware scheduling plus queued vs immediate delivery behavior.
// Depends on cloudflare:test, seeded D1 fixtures, and quiet-hours helpers.

import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { testRequest, testJson } from '../test-request';
import { seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { getAgentQuietHoursEnd, getQuietHoursEnd, isInQuietHours } from './quiet-hours';

beforeAll(seedDatabase);

describe('isInQuietHours', () => {
  it('returns false when quiet hours are incomplete', () => {
    expect(isInQuietHours(null, '08:00', 'Asia/Bangkok')).toBe(false);
    expect(isInQuietHours('22:00', null, 'Asia/Bangkok')).toBe(false);
  });

  it('handles overnight quiet hours', () => {
    for (const [instant, expected] of [
      ['2026-04-04T16:30:00.000Z', true], ['2026-04-04T03:30:00.000Z', false],
      ['2026-04-04T14:59:59.999Z', false], ['2026-04-04T15:00:00.000Z', true],
      ['2026-04-05T00:59:59.999Z', true], ['2026-04-05T01:00:00.000Z', false],
    ] as const) {
      expect(isInQuietHours('22:00', '08:00', 'Asia/Bangkok', new Date(instant))).toBe(expected);
    }
  });

  it('handles same-day quiet hours', () => {
    for (const [instant, expected] of [
      ['2026-04-04T06:30:00.000Z', true], ['2026-04-04T10:30:00.000Z', false],
      ['2026-04-04T05:59:59.999Z', false], ['2026-04-04T06:00:00.000Z', true],
      ['2026-04-04T09:59:59.999Z', true], ['2026-04-04T10:00:00.000Z', false],
    ] as const) {
      expect(isInQuietHours('13:00', '17:00', 'Asia/Bangkok', new Date(instant))).toBe(expected);
    }
  });

  it.each(['24:00', '08:60', '8:00', ''])('rejects invalid wall-clock times: %j', time => {
    const now = new Date('2026-04-04T12:00:00.000Z');
    expect(isInQuietHours(time, '23:59', 'UTC', now)).toBe(false);
    expect(isInQuietHours('00:00', time, 'UTC', now)).toBe(false);
    expect(() => getQuietHoursEnd(time, 'UTC', now)).toThrow('invalid quiet hours end');
  });

  it('treats matching endpoints as an empty window', () => {
    expect(isInQuietHours('12:00', '12:00', 'UTC', new Date('2026-04-04T12:00:00Z'))).toBe(false);
  });

  it.each([null, 'Unknown/Zone', ' UTC '])('uses UTC for absent or invalid zones: %j', zone => {
    const now = new Date('2026-04-04T23:30:00Z');
    expect(isInQuietHours('22:00', '08:00', zone, now)).toBe(true);
    expect(getQuietHoursEnd('08:00', zone ?? 'UTC', now).toISOString()).toBe('2026-04-05T08:00:00.000Z');
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

  it.each([
    ['2026-01-31T23:30:00.000Z', 'UTC', '2026-02-01T08:00:00.000Z'],
    ['2028-02-28T23:30:00.000Z', 'UTC', '2028-02-29T08:00:00.000Z'],
    ['2026-12-31T23:30:00.000Z', 'UTC', '2027-01-01T08:00:00.000Z'],
    ['2026-03-08T04:30:00.000Z', 'America/New_York', '2026-03-08T12:00:00.000Z'],
    ['2026-11-01T03:30:00.000Z', 'America/New_York', '2026-11-01T13:00:00.000Z'],
    ['2026-04-04T08:00:00.000Z', 'UTC', '2026-04-05T08:00:00.000Z'],
  ])('resolves calendar and offset boundaries at %s in %s', (instant, zone, expected) => {
    expect(getQuietHoursEnd('08:00', zone, new Date(instant)).toISOString()).toBe(expected);
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

  it('reads the timezone nested under quiet_hours (the shape the apps write)', async () => {
    // Real clients write { quiet_hours: { start, end, timezone, enabled } }.
    // A top-level $.timezone (the old query) is absent here → would fall back to
    // UTC and fire the window at the wrong wall-clock. This proves the nested read.
    await seedQuietHoursBoss('quiet-hours-nested', 'Asia/Bangkok', '22:00', '08:00', true);

    const now = new Date('2026-04-04T23:30:00.000Z');
    expect((await getAgentQuietHoursEnd(env, 'quiet-hours-nested', now))?.toISOString())
      .toBe('2026-04-05T01:00:00.000Z');
  });

  it('does not defer when quiet hours are disabled', async () => {
    // In-window, but enabled:false → the boss turned Mute off, so no deferral.
    await seedQuietHoursBoss('quiet-hours-disabled', 'UTC', '00:00', '23:59', false);

    const now = new Date('2026-04-04T12:00:00.000Z');
    expect(await getAgentQuietHoursEnd(env, 'quiet-hours-disabled', now)).toBeNull();
  });

  it('waits for every accessible boss while excluding unrelated and disabled windows', async () => {
    const agent = 'quiet-hours-multiple';
    await seedQuietHoursBoss(agent, 'UTC', '22:00', '06:00');
    await seedBossPreferences(agent, { quiet_hours: { start: '22:00', end: '08:00', timezone: 'UTC' } },
      'quiet-hours-later');
    await seedQuietHoursBoss('quiet-hours-unrelated', 'UTC', '22:00', '10:00');
    await seedBossPreferences(agent,
      { quiet_hours: { enabled: false, start: '22:00', end: '11:00', timezone: 'UTC' } }, 'quiet-disabled');
    expect((await getAgentQuietHoursEnd(env, agent, new Date('2026-04-04T23:30:00.000Z')))?.toISOString())
      .toBe('2026-04-05T08:00:00.000Z');
    expect(await getAgentQuietHoursEnd(env, agent, new Date('2026-04-04T12:00:00.000Z'))).toBeNull();
  });
});

describe('quiet-hours delivery integration', () => {
  it('queues a normal-priority message during quiet hours', async () => {
    const { headers, scheduledAt } = await createQuietHoursAgent(
      'quiet-hours-route-normal', 'hb_quiet_hours_normal_key_0000');
    const { id } = await testJson(201, testRequest('POST', 'https://test.local/api/messages', headers,
      { body: 'quiet-hours:queue-me' })) as { id: string };
    const queueRow = await env.DB
      .prepare('SELECT channel, status, scheduled_at FROM delivery_queue WHERE message_id = ?')
      .bind(id).all();
    expect(queueRow.results).toEqual([{ channel: 'api', status: 'pending', scheduled_at: scheduledAt }]);
    expect(Date.parse(scheduledAt)).toBeGreaterThan(Date.now());
    expect(await env.DB.prepare('SELECT status, body FROM messages WHERE id = ?').bind(id).first())
      .toEqual({ status: 'sent', body: 'quiet-hours:queue-me' });
  });

  it('delivers a critical message immediately during quiet hours', async () => {
    const { headers } = await createQuietHoursAgent(
      'quiet-hours-route-critical', 'hb_quiet_hours_critical_key_00');
    const { id } = await testJson(201, testRequest('POST', 'https://test.local/api/messages', headers,
      { body: 'quiet-hours:deliver-now', priority: 'critical' })) as { id: string };
    const queueCount = await env.DB
      .prepare('SELECT COUNT(*) AS total FROM delivery_queue WHERE message_id = ?')
      .bind(id).first<{ total: number }>();
    const message = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(id).first<{ status: string }>();
    expect(queueCount?.total).toBe(0);
    expect(message?.status).toBe('delivered');
  });
});

async function createQuietHoursAgent(
  agentId: string, apiKey: string,
): Promise<{ headers: Record<string, string>; scheduledAt: string }> {
  const now = Date.now();
  const end = new Date(now + 3_600_000);
  end.setUTCSeconds(0, 0);
  const keyHash = await hashApiKey(apiKey);
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash).run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO channel_configs (id, agent_id, channel, config, enabled) VALUES (?, ?, ?, ?, 1)'
  ).bind(`cfg-${agentId}`, agentId, 'api', JSON.stringify({})).run();
  await seedBossPreferences(agentId, {
    quiet_hours_start: new Date(now - 3_600_000).toISOString().slice(11, 16),
    quiet_hours_end: end.toISOString().slice(11, 16), timezone: 'UTC',
  });
  return { headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    scheduledAt: end.toISOString() };
}

async function seedQuietHoursBoss(
  agentId: string, timezone: string, start: string, end: string, enabled?: boolean,
): Promise<void> {
  const keyHash = await hashApiKey(`${agentId}-key`);
  await env.DB.prepare('INSERT OR REPLACE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash).run();
  await seedBossPreferences(agentId, enabled === undefined ? { quiet_hours: { start, end }, timezone }
    : { quiet_hours: { enabled, start, end, timezone, critical_bypass: true } });
}

async function seedBossPreferences(
  agentId: string, preferences: Record<string, unknown>, bossId = `boss-${agentId}`,
): Promise<void> {
  await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)')
    .bind(bossId, `Boss ${agentId}`, 'manager', JSON.stringify(preferences)).run();
  await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agentId).run();
}
