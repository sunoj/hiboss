// D1 limit tests: per handle (hour/day), no per-IP push bucket, the global push ceiling
// (APNs-accepted pushes only) and the global registration ceiling.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import { DAY_MS, GLOBAL_PUSH_SCOPE, GLOBAL_REGISTRATION_SCOPE, HOUR_MS, counterKey } from '../src/limits';
import {
  FIXED_NOW,
  TOKEN_A,
  TOKEN_B,
  call,
  countRows,
  mockApns,
  pushBody,
  register,
  relayEnv,
  resetDb,
} from './helpers';

beforeEach(async () => {
  await resetDb();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(FIXED_NOW);
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

async function seedCounter(scope: string, periodMs: number, count: number): Promise<void> {
  await env.DB.prepare(
    'INSERT INTO rate_counters (key, count, expires_at) VALUES (?, ?, ?) ' +
      'ON CONFLICT(key) DO UPDATE SET count = excluded.count',
  )
    .bind(counterKey(scope, periodMs, Date.now()), count, Date.now() + periodMs)
    .run();
}

async function globalCount(scope: string, periodMs: number): Promise<number> {
  const row = await env.DB.prepare('SELECT count FROM rate_counters WHERE key = ?')
    .bind(counterKey(scope, periodMs, Date.now()))
    .first<{ count: number }>();
  return row?.count ?? 0;
}

describe('per-handle limits', () => {
  it('allows 60 pushes per hour, rejects the 61st with 429, and resets next hour', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    for (let i = 0; i < 60; i += 1) {
      expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
    }
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(429);
    expect(fetchMock).toHaveBeenCalledTimes(60);
    vi.setSystemTime(FIXED_NOW + HOUR_MS);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
  });

  it('does not let one handle consume another handle’s budget', async () => {
    mockApns();
    const first = await register(TOKEN_A);
    const second = await register(TOKEN_B);
    await seedCounter(`handle:${await sha256Hex(first.handle)}`, HOUR_MS, 60);
    expect((await call('POST', '/v1/push', { body: pushBody(first.handle) })).status).toBe(429);
    expect((await call('POST', '/v1/push', { body: pushBody(second.handle) })).status).toBe(202);
  });

  it('allows 500 pushes per day and rejects the 501st', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    await seedCounter(`handle:${await sha256Hex(handle)}`, DAY_MS, 499);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
    vi.setSystemTime(FIXED_NOW + HOUR_MS);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(429);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

describe('no per-IP push limit', () => {
  it('ignores a full pre-f5c68b06 per-IP push bucket and pushes from one shared address', async () => {
    mockApns();
    const { handle } = await register(TOKEN_A);
    const other = await register(TOKEN_B);
    const ip = '2a06:98c0:3600::103';
    await seedCounter(`ip:push:${await sha256Hex(ip)}`, HOUR_MS, 600);
    expect((await call('POST', '/v1/push', { body: pushBody(handle), ip })).status).toBe(202);
    expect((await call('POST', '/v1/push', { body: pushBody(other.handle), ip })).status).toBe(202);
  });
});

describe('global daily ceiling', () => {
  it('answers 503 at GLOBAL_DAILY_PUSH_LIMIT accepted pushes and resets the next UTC day', async () => {
    const fetchMock = mockApns();
    const relay = await relayEnv({ GLOBAL_DAILY_PUSH_LIMIT: '2' });
    const first = await register(TOKEN_A);
    const second = await register(TOKEN_B);
    expect((await call('POST', '/v1/push', { body: pushBody(first.handle), env: relay })).status).toBe(202);
    expect((await call('POST', '/v1/push', { body: pushBody(second.handle), env: relay })).status).toBe(202);
    expect((await call('POST', '/v1/push', { body: pushBody(first.handle), env: relay })).status).toBe(503);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    vi.setSystemTime(FIXED_NOW + DAY_MS);
    expect((await call('POST', '/v1/push', { body: pushBody(first.handle), env: relay })).status).toBe(202);
  });

  it('defaults to 200,000 per day when the variable is missing or invalid', async () => {
    mockApns();
    const { handle } = await register();
    const relay = await relayEnv({ GLOBAL_DAILY_PUSH_LIMIT: 'lots' });
    await seedCounter(GLOBAL_PUSH_SCOPE, DAY_MS, 199_999);
    expect((await call('POST', '/v1/push', { body: pushBody(handle), env: relay })).status).toBe(202);
    expect((await call('POST', '/v1/push', { body: pushBody(handle), env: relay })).status).toBe(503);
  });

  it.each([
    [410, 'Unregistered', 410],
    [400, 'BadDeviceToken', 410],
    [500, 'InternalServerError', 502],
  ])('does not count a push APNs answered %i %s', async (apnsStatus, reason, relayStatus) => {
    const relay = await relayEnv({ GLOBAL_DAILY_PUSH_LIMIT: '1' });
    const rejected = await register(TOKEN_A);
    const accepted = await register(TOKEN_B);
    mockApns(apnsStatus, reason);
    expect((await call('POST', '/v1/push', { body: pushBody(rejected.handle), env: relay })).status).toBe(relayStatus);
    expect(await globalCount(GLOBAL_PUSH_SCOPE, DAY_MS)).toBe(0);
    mockApns();
    expect((await call('POST', '/v1/push', { body: pushBody(accepted.handle), env: relay })).status).toBe(202);
    expect(await globalCount(GLOBAL_PUSH_SCOPE, DAY_MS)).toBe(1);
  });

  it('writes no row at all for unknown or invalid handles', async () => {
    const fetchMock = mockApns();
    for (let i = 0; i < 5; i += 1) {
      await call('POST', '/v1/push', { body: pushBody(`${'A'.repeat(42)}${i}`), ip: `2001:db8::${i}` });
    }
    await call('POST', '/v1/push', { body: pushBody('', { kind: 'nope' }) });
    expect(await countRows('rate_counters')).toBe(0);
    expect(await countRows('registrations')).toBe(0);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe('global registration ceiling', () => {
  const body = { apnsToken: TOKEN_A, environment: 'production' };

  it('answers 503 at 5,000 new registrations per hour without storing, and resets next hour', async () => {
    await seedCounter(GLOBAL_REGISTRATION_SCOPE, HOUR_MS, 4_999);
    expect((await call('POST', '/v1/registrations', { body })).status).toBe(201);
    const over = await call('POST', '/v1/registrations', { body });
    expect(over.status).toBe(503);
    expect(await over.json()).toEqual({ error: 'unavailable' });
    expect(await countRows('registrations')).toBe(1);
    expect(await globalCount(GLOBAL_REGISTRATION_SCOPE, HOUR_MS)).toBe(5_000);
    vi.setSystemTime(FIXED_NOW + HOUR_MS);
    expect((await call('POST', '/v1/registrations', { body })).status).toBe(201);
  });

  it('counts only successful registrations, not rejected ones or token rotation', async () => {
    await call('POST', '/v1/registrations', { body: { ...body, environment: 'staging' } });
    expect(await globalCount(GLOBAL_REGISTRATION_SCOPE, HOUR_MS)).toBe(0);
    const { deviceSecret } = await register();
    await call('PUT', '/v1/registrations/self', { body, secret: deviceSecret });
    expect(await globalCount(GLOBAL_REGISTRATION_SCOPE, HOUR_MS)).toBe(1);
  });
});
