// Token verification tests: POST and PUT store a token only after APNs accepts one background
// push to it; a rejected token gets 400 invalid_token and an APNs failure 503, both writing nothing.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { VERIFY_TIMEOUT_MS } from '../src/apns';
import {
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

beforeEach(resetDb);
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

const tokenBody = (apnsToken = TOKEN_A, environment = 'production') => ({ apnsToken, environment });

async function expectNothingStored(): Promise<void> {
  expect(await countRows('registrations')).toBe(0);
  expect(await countRows('rate_counters')).toBe(0);
}

describe('POST /v1/registrations token check', () => {
  it('sends exactly one background push to a valid token, then stores it', async () => {
    const fetchMock = mockApns();
    const response = await call('POST', '/v1/registrations', { body: tokenBody(TOKEN_A, 'sandbox') });
    expect(response.status).toBe(201);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = apnsCalls(fetchMock, 'background')[0];
    expect(url).toBe(`https://api.sandbox.push.apple.com/3/device/${TOKEN_A}`);
    const headers = init.headers as Record<string, string>;
    expect(headers['apns-push-type']).toBe('background');
    expect(headers['apns-priority']).toBe('5');
    expect(headers['apns-topic']).toBe('ai.hiboss.app');
    expect(headers.authorization).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    expect(headers).not.toHaveProperty('apns-collapse-id');
    expect(JSON.parse(init.body as string)).toEqual({ aps: { 'content-available': 1 } });
    expect(init.signal).toBeInstanceOf(AbortSignal);
    expect(await countRows('registrations')).toBe(1);
  });

  it('uses the production host for a production token', async () => {
    const fetchMock = mockApns();
    await register(TOKEN_A, 'production');
    expect(fetchMock.mock.calls[0][0]).toBe(`https://api.push.apple.com/3/device/${TOKEN_A}`);
  });

  it.each([
    [400, 'BadDeviceToken'],
    [400, 'DeviceTokenNotForTopic'],
    [410, 'Unregistered'],
  ])('answers APNs %s %s with 400 invalid_token and stores nothing', async (status, reason) => {
    mockApns(200, undefined, { status, reason });
    const response = await call('POST', '/v1/registrations', { body: tokenBody() });
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'invalid_token' });
    await expectNothingStored();
  });

  it.each([
    [500, 'InternalServerError'],
    [503, 'ServiceUnavailable'],
    [403, 'ExpiredProviderToken'],
    [429, 'TooManyRequests'],
  ])('answers APNs %s %s with 503 and stores nothing', async (status, reason) => {
    mockApns(200, undefined, { status, reason });
    const response = await call('POST', '/v1/registrations', { body: tokenBody() });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: 'unavailable' });
    await expectNothingStored();
  });

  it('answers a transport error with 503 and stores nothing', async () => {
    vi.stubGlobal('fetch', vi.fn<typeof fetch>(async () => Promise.reject(new TypeError('network'))));
    expect((await call('POST', '/v1/registrations', { body: tokenBody() })).status).toBe(503);
    await expectNothingStored();
  });

  it('gives up after the timeout with 503 and stores nothing', async () => {
    const hang = vi.fn<typeof fetch>(
      (_url, init) =>
        new Promise((_resolve, reject) => init?.signal?.addEventListener('abort', () => reject(init.signal?.reason))),
    );
    vi.stubGlobal('fetch', hang);
    const started = Date.now();
    expect((await call('POST', '/v1/registrations', { body: tokenBody() })).status).toBe(503);
    expect(Date.now() - started).toBeGreaterThanOrEqual(VERIFY_TIMEOUT_MS - 100);
    await expectNothingStored();
  });

  it('answers 503 without calling APNs when the key is not configured', async () => {
    const fetchMock = mockApns();
    const relay = await relayEnv({ APNS_KEY_ID: undefined });
    expect((await call('POST', '/v1/registrations', { body: tokenBody(), env: relay })).status).toBe(503);
    expect(fetchMock).not.toHaveBeenCalled();
    await expectNothingStored();
  });

  it('keeps the existing registration when a re-registration is rejected', async () => {
    mockApns();
    const { handle } = await register(TOKEN_A);
    mockApns(200, undefined, { status: 400, reason: 'BadDeviceToken' });
    expect((await call('POST', '/v1/registrations', { body: tokenBody() })).status).toBe(400);
    expect(await countRows('registrations')).toBe(1);
    mockApns();
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
  });
});

describe('PUT /v1/registrations/self token check', () => {
  async function rotate(secret: string, body = tokenBody(TOKEN_B, 'sandbox')): Promise<Response> {
    return call('PUT', '/v1/registrations/self', { body, secret });
  }

  async function storedToken(): Promise<string | undefined> {
    const row = await env.DB.prepare('SELECT apns_token FROM registrations').first<{ apns_token: string }>();
    return row?.apns_token;
  }

  it('verifies the new token in the requested environment before rotating', async () => {
    const fetchMock = mockApns();
    const { deviceSecret } = await register(TOKEN_A);
    expect((await rotate(deviceSecret)).status).toBe(204);
    const checks = apnsCalls(fetchMock, 'background');
    expect(checks.map(([url]) => url)).toEqual([
      `https://api.push.apple.com/3/device/${TOKEN_A}`,
      `https://api.sandbox.push.apple.com/3/device/${TOKEN_B}`,
    ]);
    expect(await storedToken()).toBe(TOKEN_B);
  });

  it('answers a rejected new token with 400 invalid_token and keeps the old token', async () => {
    mockApns();
    const { deviceSecret } = await register(TOKEN_A);
    mockApns(200, undefined, { status: 400, reason: 'BadDeviceToken' });
    const response = await rotate(deviceSecret);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'invalid_token' });
    expect(await storedToken()).toBe(TOKEN_A);
  });

  it('answers an APNs failure with 503 and keeps the old token', async () => {
    mockApns();
    const { deviceSecret } = await register(TOKEN_A);
    mockApns(200, undefined, { status: 500 });
    expect((await rotate(deviceSecret)).status).toBe(503);
    expect(await storedToken()).toBe(TOKEN_A);
  });

  it('answers an unknown secret with 410 without calling APNs', async () => {
    mockApns();
    await register(TOKEN_A);
    const fetchMock = mockApns();
    expect((await rotate('A'.repeat(43))).status).toBe(410);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
