// Abuse limit tests: per handle (hour/day), per source IP (push/registration), global ceiling.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import { DAY_MS, HOUR_MS, counterKey } from '../src/limits';
import { FIXED_NOW, TOKEN_A, TOKEN_B, call, mockApns, pushBody, register, relayEnv, resetDb } from './helpers';

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

async function ipScope(bucket: 'push' | 'reg', ip: string): Promise<string> {
  return `ip:${bucket}:${await sha256Hex(ip)}`;
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

describe('per-IP limits', () => {
  it('rejects pushes above 600 per hour from one IP before looking at the handle', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    await seedCounter(await ipScope('push', '198.51.100.7'), HOUR_MS, 600);
    const limited = await call('POST', '/v1/push', { body: pushBody(handle), ip: '198.51.100.7' });
    expect(limited.status).toBe(429);
    expect(fetchMock).not.toHaveBeenCalled();
    const handleCounters = await env.DB.prepare("SELECT COUNT(*) AS n FROM rate_counters WHERE key LIKE 'handle:%'")
      .first<{ n: number }>();
    expect(handleCounters?.n).toBe(0);
    expect((await call('POST', '/v1/push', { body: pushBody(handle), ip: '198.51.100.8' })).status).toBe(202);
  });

  it('allows 30 registrations per hour per IP and rejects the 31st without storing it', async () => {
    for (let i = 0; i < 30; i += 1) await register(TOKEN_A, 'production', '192.0.2.9');
    const body = { apnsToken: TOKEN_A, environment: 'production' };
    expect((await call('POST', '/v1/registrations', { body, ip: '192.0.2.9' })).status).toBe(429);
    const rows = await env.DB.prepare('SELECT COUNT(*) AS n FROM registrations').first<{ n: number }>();
    expect(rows?.n).toBe(30);
    expect((await call('POST', '/v1/registrations', { body, ip: '192.0.2.10' })).status).toBe(201);
  });

  it('applies the registration bucket to token rotation and deletion', async () => {
    const { deviceSecret } = await register(TOKEN_A, 'production', '192.0.2.20');
    await seedCounter(await ipScope('reg', '192.0.2.20'), HOUR_MS, 30);
    const body = { apnsToken: TOKEN_B, environment: 'production' };
    const put = await call('PUT', '/v1/registrations/self', { body, secret: deviceSecret, ip: '192.0.2.20' });
    expect(put.status).toBe(429);
    const del = await call('DELETE', '/v1/registrations/self', { secret: deviceSecret, ip: '192.0.2.20' });
    expect(del.status).toBe(429);
  });
});

describe('global daily ceiling', () => {
  it('answers 503 above GLOBAL_DAILY_PUSH_LIMIT and resets the next UTC day', async () => {
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

  it('falls back to the default ceiling when the variable is missing or invalid', async () => {
    mockApns();
    const { handle } = await register();
    const relay = await relayEnv({ GLOBAL_DAILY_PUSH_LIMIT: 'lots' });
    await seedCounter('global', DAY_MS, 49_999);
    expect((await call('POST', '/v1/push', { body: pushBody(handle), env: relay })).status).toBe(202);
    expect((await call('POST', '/v1/push', { body: pushBody(handle), env: relay })).status).toBe(503);
  });
});
