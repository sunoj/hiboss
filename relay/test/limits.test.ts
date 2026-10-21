// D1 limit tests: per handle (hour/day), no per-IP push bucket, no relay-wide push ceiling,
// the global registration ceiling, and the rate-limit bindings configured in the example.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import * as limits from '../src/limits';
import { DAY_MS, GLOBAL_REGISTRATION_SCOPE, HOUR_MS, counterKey } from '../src/limits';
import type { Env } from '../src/types';
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

describe('no relay-wide push ceiling', () => {
  it('has no global push ceiling in code or configuration', () => {
    expect(Object.keys(limits)).toEqual(expect.not.arrayContaining(['globalPushCheck', 'GLOBAL_PUSH_SCOPE']));
    expect(env.WRANGLER_EXAMPLE).not.toMatch(/GLOBAL_DAILY_PUSH_LIMIT|\[vars\]/);
  });

  it('bounds pushes only per handle: a full legacy global counter and a ceiling variable are ignored', async () => {
    const fetchMock = mockApns();
    const relay = await relayEnv({ GLOBAL_DAILY_PUSH_LIMIT: '1' } as Partial<Env>);
    const first = await register(TOKEN_A);
    const second = await register(TOKEN_B);
    await seedCounter('global', DAY_MS, 1_000_000_000);
    for (const handle of [first.handle, second.handle, first.handle]) {
      expect((await call('POST', '/v1/push', { body: pushBody(handle), env: relay })).status).toBe(202);
    }
    expect(fetchMock).toHaveBeenCalledTimes(3);
    const rows = await env.DB.prepare('SELECT key FROM rate_counters').all<{ key: string }>();
    const scopes = new Set(rows.results.map((row) => row.key.split('|')[0]));
    expect([...scopes].sort()).toEqual(
      ['global', 'global:reg', `handle:${await sha256Hex(first.handle)}`, `handle:${await sha256Hex(second.handle)}`].sort(),
    );
    expect(await globalCount('global', DAY_MS)).toBe(1_000_000_000);
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

  it('answers 503 at 50,000 new registrations per hour without storing, and resets next hour', async () => {
    await seedCounter(GLOBAL_REGISTRATION_SCOPE, HOUR_MS, 49_999);
    expect((await call('POST', '/v1/registrations', { body })).status).toBe(201);
    const over = await call('POST', '/v1/registrations', { body });
    expect(over.status).toBe(503);
    expect(await over.json()).toEqual({ error: 'unavailable' });
    expect(await countRows('registrations')).toBe(1);
    expect(await globalCount(GLOBAL_REGISTRATION_SCOPE, HOUR_MS)).toBe(50_000);
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

describe('configured rate-limit bindings', () => {
  it('limits pushes 600/min, registrations 5/min and /self calls 30/min per source key', () => {
    const blocks = env.WRANGLER_EXAMPLE.split('[[ratelimits]]').slice(1);
    const parsed = Object.fromEntries(
      blocks.map((block) => {
        const name = /name = "([A-Z_]+)"/.exec(block)?.[1];
        const simple = /simple = \{ limit = (\d+), period = (\d+) \}/.exec(block);
        return [name, simple && [Number(simple[1]), Number(simple[2])]];
      }),
    );
    expect(parsed).toEqual({
      PUSH_RATE_LIMITER: [600, 60],
      REGISTRATION_RATE_LIMITER: [5, 60],
      SELF_RATE_LIMITER: [30, 60],
    });
  });
});
