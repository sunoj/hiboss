// Request-gate tests: rate-limit keys, 429 before any D1 access, body size caps, and no
// IP-derived data in D1.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import { mintHandle } from '../src/handles';
import { clientKey, ipv6Prefix64 } from '../src/limits';
import {
  TEST_HANDLE_KEY,
  forbiddenDb,
  TOKEN_A,
  TOKEN_B,
  call,
  countRows,
  fakeLimiter,
  mockApns,
  pushBody,
  register,
  relayEnv,
  resetDb,
} from './helpers';

beforeEach(resetDb);
afterEach(() => vi.unstubAllGlobals());

const tokenBody = { apnsToken: TOKEN_A, environment: 'production' };


describe('registration source key', () => {
  const keyFor = (headers: Record<string, string>) => clientKey(new Request('https://push.test/', { headers }));

  it('buckets IPv6 by /64 and IPv4 by full address', () => {
    expect(keyFor({ 'CF-Connecting-IP': '2001:DB8:0:1:aaaa::1' })).toBe('2001:db8:0:1::/64');
    expect(keyFor({ 'CF-Connecting-IP': '2001:db8:0:1:ffff:ffff:ffff:ffff' })).toBe('2001:db8:0:1::/64');
    expect(keyFor({ 'CF-Connecting-IP': '2001:db8:0:2::1' })).toBe('2001:db8:0:2::/64');
    expect(keyFor({ 'CF-Connecting-IP': '198.51.100.7' })).toBe('198.51.100.7');
    expect(keyFor({ 'CF-Connecting-IP': '::ffff:198.51.100.7' })).toBe('198.51.100.7');
    expect(keyFor({ 'X-Forwarded-For': '198.51.100.9' })).toBe('unknown');
  });

  it('expands compressed IPv6 forms', () => {
    expect(ipv6Prefix64('::1')).toBe('0:0:0:0::/64');
    expect(ipv6Prefix64('2001:0db8:0000:0007::')).toBe('2001:db8:0:7::/64');
    expect(ipv6Prefix64('2001:db8::')).toBe('2001:db8:0:0::/64');
  });

  it('ignores CF-Worker', () => {
    expect(keyFor({ 'CF-Worker': 'boss.example.com', 'CF-Connecting-IP': '198.51.100.7' })).toBe('198.51.100.7');
  });

  it('passes the address to the registration limiters and the handle digest to the handle limiter', async () => {
    mockApns();
    const relay = await relayEnv();
    const headers = { 'CF-Worker': 'boss.example.com' };
    const handle = await mintHandle(TEST_HANDLE_KEY);
    await call('POST', '/v1/registrations', { body: tokenBody, env: relay, headers, ip: '2001:db8:0:9::5' });
    await call('POST', '/v1/push', { body: pushBody(handle), env: relay, headers, ip: '2a06:98c0:3600::103' });
    const self = { secret: 'x', env: relay, headers, ip: '198.51.100.7' };
    await call('PUT', '/v1/registrations/self', { body: tokenBody, ...self });
    await call('DELETE', '/v1/registrations/self', self);
    const keys = (limiter: RateLimit) => (limiter as ReturnType<typeof fakeLimiter>).keys;
    expect(keys(relay.REGISTRATION_RATE_LIMITER)).toEqual(['2001:db8:0:9::/64']);
    expect(keys(relay.HANDLE_RATE_LIMITER)).toEqual([await sha256Hex(handle)]);
    expect(keys(relay.SELF_RATE_LIMITER)).toEqual(['198.51.100.7', '198.51.100.7']);
  });
});

describe('rate limits', () => {
  it('answers 429 to every route without touching D1 when the limiter refuses', async () => {
    const fetchMock = mockApns();
    const relay = await relayEnv({
      DB: forbiddenDb,
      HANDLE_RATE_LIMITER: fakeLimiter(false),
      REGISTRATION_RATE_LIMITER: fakeLimiter(false),
      SELF_RATE_LIMITER: fakeLimiter(false),
    });
    const attempts = [
      await call('POST', '/v1/push', { body: pushBody(await mintHandle(TEST_HANDLE_KEY)), env: relay }),
      await call('POST', '/v1/registrations', { body: tokenBody, env: relay }),
      await call('PUT', '/v1/registrations/self', { body: tokenBody, secret: 'x', env: relay }),
      await call('DELETE', '/v1/registrations/self', { secret: 'x', env: relay }),
    ];
    const seen = await Promise.all(attempts.map(async (r) => `${r.status} ${await r.text()}`));
    expect(seen).toEqual(Array(4).fill('429 {"error":"rate_limited"}'));
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('keeps the push, registration and /self limiters separate', async () => {
    mockApns();
    const relay = await relayEnv({ REGISTRATION_RATE_LIMITER: fakeLimiter(false) });
    const { handle, deviceSecret } = await register();
    expect((await call('POST', '/v1/registrations', { body: tokenBody, env: relay })).status).toBe(429);
    expect((await call('POST', '/v1/push', { body: pushBody(handle), env: relay })).status).toBe(202);
    const put = await call('PUT', '/v1/registrations/self', { body: tokenBody, secret: deviceSecret, env: relay });
    expect(put.status).toBe(204);
    const selfLimited = await relayEnv({ SELF_RATE_LIMITER: fakeLimiter(false) });
    expect((await call('DELETE', '/v1/registrations/self', { secret: deviceSecret, env: selfLimited })).status).toBe(429);
    expect((await call('POST', '/v1/registrations', { body: tokenBody, env: selfLimited })).status).toBe(201);
  });
});

describe('body size', () => {
  it.each([
    ['POST', '/v1/registrations'],
    ['PUT', '/v1/registrations/self'],
    ['POST', '/v1/push'],
  ])('%s %s rejects a missing or oversized Content-Length before the limiter', async (method, path) => {
    const relay = await relayEnv({ DB: forbiddenDb });
    const body = path === '/v1/push' ? pushBody('A'.repeat(43)) : tokenBody;
    for (const contentLength of [null, '8193', '-1', 'abc']) {
      const response = await call(method, path, { body, contentLength, secret: 'x', env: relay });
      expect(response.status).toBe(400);
    }
    expect((relay.HANDLE_RATE_LIMITER as ReturnType<typeof fakeLimiter>).keys).toEqual([]);
    expect((relay.REGISTRATION_RATE_LIMITER as ReturnType<typeof fakeLimiter>).keys).toEqual([]);
    expect((relay.SELF_RATE_LIMITER as ReturnType<typeof fakeLimiter>).keys).toEqual([]);
  });

  it('enforces the limit while reading when Content-Length understates the body', async () => {
    const raw = JSON.stringify({ ...tokenBody, pad: 'x'.repeat(9000) });
    expect((await call('POST', '/v1/registrations', { raw, contentLength: '100' })).status).toBe(400);
    expect(await countRows('registrations')).toBe(0);
  });

  it('accepts a body of exactly 8,192 bytes', async () => {
    mockApns();
    const base = JSON.stringify({ apnsToken: TOKEN_A, environment: 'production' });
    const raw = base.replace('{', '{' + ' '.repeat(8192 - base.length));
    expect((await call('POST', '/v1/registrations', { raw })).status).toBe(201);
  });
});

describe('stored data', () => {
  it('keeps no IP-derived data in D1', async () => {
    mockApns();
    const ip = '2001:db8:0:42::7';
    const { handle, deviceSecret } = await register(TOKEN_A, 'production', ip);
    await call('POST', '/v1/push', { body: pushBody(handle), ip });
    const rotated = { ...tokenBody, apnsToken: TOKEN_B };
    await call('PUT', '/v1/registrations/self', { body: rotated, secret: deviceSecret, ip });
    const rows = await Promise.all(
      ['registrations', 'rate_counters'].map((t) => env.DB.prepare(`SELECT * FROM ${t}`).all()),
    );
    const dump = JSON.stringify(rows.map((r) => r.results));
    for (const needle of [ip, '2001:db8:0:42', await sha256Hex(ip), '|2001']) {
      expect(dump).not.toContain(needle);
    }
  });
});
