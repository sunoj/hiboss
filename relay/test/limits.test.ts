// D1 limit tests: per device (hour/day, keyed on the APNs token), no per-IP push bucket, no
// relay-wide push or registration ceiling, and the rate-limit bindings configured in the example.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import * as limits from '../src/limits';
import { DAY_MS, HOUR_MS, counterKey } from '../src/limits';
import type { Env } from '../src/types';
import {
  FIXED_NOW,
  TOKEN_A,
  TOKEN_B,
  apnsCalls,
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

const deviceScope = async (token: string) => `token:${await sha256Hex(token)}`;

async function storedCount(scope: string, periodMs: number): Promise<number> {
  const row = await env.DB.prepare('SELECT count FROM rate_counters WHERE key = ?')
    .bind(counterKey(scope, periodMs, Date.now()))
    .first<{ count: number }>();
  return row?.count ?? 0;
}

describe('per-device limits', () => {
  it('allows 60 pushes per hour, rejects the 61st with 429, and resets next hour', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    for (let i = 0; i < 60; i += 1) {
      expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
    }
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(429);
    expect(apnsCalls(fetchMock, 'alert')).toHaveLength(60);
    expect(await storedCount(await deviceScope(TOKEN_A), HOUR_MS)).toBe(60);
    expect(await storedCount(await deviceScope(TOKEN_A), DAY_MS)).toBe(60);
    vi.setSystemTime(FIXED_NOW + HOUR_MS);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
  });

  it('keeps 60 per hour across 5 re-registrations of one token', async () => {
    const fetchMock = mockApns();
    let accepted = 0;
    for (let round = 0; round < 5; round += 1) {
      const { handle } = await register(TOKEN_A);
      for (let i = 0; i < 61; i += 1) {
        if ((await call('POST', '/v1/push', { body: pushBody(handle) })).status === 202) accepted += 1;
      }
    }
    expect(accepted).toBe(60);
    expect(apnsCalls(fetchMock, 'alert')).toHaveLength(60);
    expect(apnsCalls(fetchMock, 'background')).toHaveLength(5);
  });

  it('does not let one device consume another device’s budget', async () => {
    mockApns();
    const first = await register(TOKEN_A);
    const second = await register(TOKEN_B);
    await seedCounter(await deviceScope(TOKEN_A), HOUR_MS, 60);
    expect((await call('POST', '/v1/push', { body: pushBody(first.handle) })).status).toBe(429);
    expect((await call('POST', '/v1/push', { body: pushBody(second.handle) })).status).toBe(202);
  });

  it('writes nothing for a push over the hourly limit', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    await seedCounter(await deviceScope(TOKEN_A), HOUR_MS, 60);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(429);
    expect(await countRows('rate_counters')).toBe(1);
    expect(await storedCount(await deviceScope(TOKEN_A), HOUR_MS)).toBe(60);
    expect(apnsCalls(fetchMock, 'alert')).toHaveLength(0);
  });

  it('writes nothing for a push over the daily limit', async () => {
    mockApns();
    const { handle } = await register();
    await seedCounter(await deviceScope(TOKEN_A), DAY_MS, 500);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(429);
    expect(await countRows('rate_counters')).toBe(1);
    expect(await storedCount(await deviceScope(TOKEN_A), DAY_MS)).toBe(500);
  });

  it('allows 500 pushes per day and rejects the 501st', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    await seedCounter(await deviceScope(TOKEN_A), DAY_MS, 499);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
    vi.setSystemTime(FIXED_NOW + HOUR_MS);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(429);
    expect(apnsCalls(fetchMock, 'alert')).toHaveLength(1);
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

  it('bounds pushes only per device: a full legacy global counter and a ceiling variable are ignored', async () => {
    const fetchMock = mockApns();
    const relay = await relayEnv({ GLOBAL_DAILY_PUSH_LIMIT: '1' } as Partial<Env>);
    const first = await register(TOKEN_A);
    const second = await register(TOKEN_B);
    await seedCounter('global', DAY_MS, 1_000_000_000);
    for (const handle of [first.handle, second.handle, first.handle]) {
      expect((await call('POST', '/v1/push', { body: pushBody(handle), env: relay })).status).toBe(202);
    }
    expect(apnsCalls(fetchMock, 'alert')).toHaveLength(3);
    const rows = await env.DB.prepare('SELECT key FROM rate_counters').all<{ key: string }>();
    const scopes = new Set(rows.results.map((row) => row.key.split('|')[0]));
    expect([...scopes].sort()).toEqual(
      ['global', await deviceScope(TOKEN_A), await deviceScope(TOKEN_B)].sort(),
    );
    expect(await storedCount('global', DAY_MS)).toBe(1_000_000_000);
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

describe('no registration ceiling', () => {
  it('has no registration ceiling in code', () => {
    expect(Object.keys(limits)).toEqual(
      expect.not.arrayContaining(['globalRegistrationCheck', 'GLOBAL_REGISTRATION_SCOPE', 'ceilingReached']),
    );
    expect(Object.keys(limits.LIMITS)).toEqual(['devicePerHour', 'devicePerDay']);
  });

  it('ignores a full legacy registration counter and writes no counter on registration', async () => {
    mockApns();
    await seedCounter('global:reg', HOUR_MS, 1_000_000);
    await register(TOKEN_A);
    await register(TOKEN_B);
    expect(await countRows('registrations')).toBe(2);
    expect(await countRows('rate_counters')).toBe(1);
  });
});

describe('configured rate-limit bindings', () => {
  it('limits pushes 60/min per handle, registrations 5/min and /self calls 30/min per address', () => {
    const blocks = env.WRANGLER_EXAMPLE.split('[[ratelimits]]').slice(1);
    const parsed = Object.fromEntries(
      blocks.map((block) => {
        const name = /name = "([A-Z_]+)"/.exec(block)?.[1];
        const simple = /simple = \{ limit = (\d+), period = (\d+) \}/.exec(block);
        return [name, simple && [Number(simple[1]), Number(simple[2])]];
      }),
    );
    expect(parsed).toEqual({
      HANDLE_RATE_LIMITER: [60, 60],
      REGISTRATION_RATE_LIMITER: [5, 60],
      SELF_RATE_LIMITER: [30, 60],
    });
  });

  it('has no per-source push limiter in code or configuration', () => {
    expect(Object.keys(limits)).toEqual(expect.not.arrayContaining(['sourceKey', 'sourceLimited']));
    expect(env.WRANGLER_EXAMPLE).not.toMatch(/PUSH_RATE_LIMITER|CF-Worker/);
  });
});
