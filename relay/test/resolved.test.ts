// `resolved` kind tests: background APNs request, strict body, its own device bucket, 410 cleanup.
// A resolution never consumes the alert budget, and alerts never starve resolutions.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import { DAY_MS, HOUR_MS, counterKey } from '../src/limits';
import {
  CIPHERTEXT,
  FIXED_NOW,
  TOKEN_A,
  apnsCalls,
  call,
  countRows,
  mockApns,
  pushBody,
  register,
  resetDb,
  resolvedBody,
} from './helpers';

beforeEach(async () => {
  await resetDb();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(FIXED_NOW);
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

async function seedCounter(scope: string, periodMs: number, count: number): Promise<void> {
  await env.DB.prepare('INSERT INTO rate_counters (key, count, expires_at) VALUES (?, ?, ?)')
    .bind(counterKey(scope, periodMs, Date.now()), count, Date.now() + periodMs)
    .run();
}

describe('POST /v1/push kind resolved', () => {
  it('sends a background push with the ciphertext in `e` and no alert fields', async () => {
    const fetchMock = mockApns();
    const { handle } = await register(TOKEN_A, 'production');
    expect((await call('POST', '/v1/push', { body: resolvedBody(handle) })).status).toBe(202);
    const sent = apnsCalls(fetchMock, 'resolved');
    expect(sent).toHaveLength(1);
    const [url, init] = sent[0];
    const headers = init.headers as Record<string, string>;
    expect(url).toBe(`https://api.push.apple.com/3/device/${TOKEN_A}`);
    expect(headers['apns-push-type']).toBe('background');
    expect(headers['apns-priority']).toBe('5');
    expect(headers['apns-topic']).toBe('ai.hiboss.app');
    expect(headers['apns-collapse-id']).toBeUndefined();
    expect(JSON.parse(init.body as string)).toEqual({ aps: { 'content-available': 1 }, e: CIPHERTEXT });
    expect(apnsCalls(fetchMock, 'alert')).toHaveLength(0);
  });

  it.each([
    ['priority 10', { priority: 10 }],
    ['missing priority', { priority: undefined }],
    ['interruption', { interruption: 'passive' }],
    ['sound', { sound: false }],
    ['collapseId', { collapseId: 'msg_1' }],
  ])('rejects %s with 400 and sends nothing', async (_name, extra) => {
    const fetchMock = mockApns();
    const { handle } = await register();
    const response = await call('POST', '/v1/push', { body: resolvedBody(handle, extra) });
    expect(response.status).toBe(400);
    expect(apnsCalls(fetchMock, 'resolved')).toHaveLength(0);
  });

  it('deletes the registration and answers 410 when APNs answers 410', async () => {
    mockApns(410, 'Unregistered');
    const { handle } = await register();
    expect((await call('POST', '/v1/push', { body: resolvedBody(handle) })).status).toBe(410);
    expect(await countRows('registrations')).toBe(0);
  });

  it('answers 502 and keeps the registration on other APNs failures', async () => {
    mockApns(500, 'InternalServerError');
    const { handle } = await register();
    expect((await call('POST', '/v1/push', { body: resolvedBody(handle) })).status).toBe(502);
    expect(await countRows('registrations')).toBe(1);
  });
});

describe('resolved device bucket', () => {
  it('still sends resolutions when the alert bucket is full, and alerts when resolutions are', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    const digest = await sha256Hex(TOKEN_A);
    await seedCounter(`token:${digest}`, HOUR_MS, 60);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(429);
    expect((await call('POST', '/v1/push', { body: resolvedBody(handle) })).status).toBe(202);
    await env.DB.prepare('DELETE FROM rate_counters').run();
    await seedCounter(`resolved:token:${digest}`, DAY_MS, 500);
    expect((await call('POST', '/v1/push', { body: resolvedBody(handle) })).status).toBe(429);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
    expect(apnsCalls(fetchMock, 'resolved')).toHaveLength(1);
    expect(apnsCalls(fetchMock, 'alert')).toHaveLength(1);
  });

  it('allows 60 resolutions per hour and rejects the 61st', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    for (let i = 0; i < 60; i += 1) {
      expect((await call('POST', '/v1/push', { body: resolvedBody(handle) })).status).toBe(202);
    }
    expect((await call('POST', '/v1/push', { body: resolvedBody(handle) })).status).toBe(429);
    expect(apnsCalls(fetchMock, 'resolved')).toHaveLength(60);
  });
});
