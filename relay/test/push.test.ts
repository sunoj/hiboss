// Push API tests: APNs request shape, validation, no-oracle handles, 410 cleanup, no logs.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { CIPHERTEXT, TOKEN_A, call, countRows, mockApns, pushBody, register, relayEnv, resetDb } from './helpers';

beforeEach(resetDb);
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function apnsRequest(fetchMock: ReturnType<typeof mockApns>, index = 0) {
  const [url, init] = fetchMock.mock.calls[index] as [string, RequestInit];
  const headers = init.headers as Record<string, string>;
  return { url, headers, payload: JSON.parse(init.body as string) as Record<string, unknown> };
}

describe('POST /v1/push APNs request', () => {
  it('sends a generic active decision alert with sound and ciphertext in `e`', async () => {
    const fetchMock = mockApns();
    const { handle } = await register(TOKEN_A, 'production');
    const response = await call('POST', '/v1/push', {
      body: pushBody(handle, { kind: 'decision', collapseId: 'msg_123-abc' }),
    });
    expect(response.status).toBe(202);
    const { url, headers, payload } = apnsRequest(fetchMock);
    expect(url).toBe(`https://api.push.apple.com/3/device/${TOKEN_A}`);
    expect(headers['apns-topic']).toBe('ai.hiboss.app');
    expect(headers['apns-push-type']).toBe('alert');
    expect(headers['apns-priority']).toBe('10');
    expect(headers['apns-collapse-id']).toBe('msg_123-abc');
    expect(headers.authorization).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    expect(payload).toEqual({
      aps: {
        alert: { 'title-loc-key': 'HIBOSS_PUSH_TITLE', 'loc-key': 'HIBOSS_PUSH_DECISION' },
        sound: 'default',
        'interruption-level': 'active',
        'mutable-content': 1,
        'thread-id': 'msg_123-abc',
      },
      e: CIPHERTEXT,
    });
  });

  it.each([
    ['message', 'HIBOSS_PUSH_MESSAGE'],
    ['system', 'HIBOSS_PUSH_SYSTEM'],
  ])('sends %s with its loc-key and no collapse id', async (kind, locKey) => {
    const fetchMock = mockApns();
    const { handle } = await register(TOKEN_A, 'sandbox');
    expect((await call('POST', '/v1/push', { body: pushBody(handle, { kind }) })).status).toBe(202);
    const { url, headers, payload } = apnsRequest(fetchMock);
    expect(url).toBe(`https://api.sandbox.push.apple.com/3/device/${TOKEN_A}`);
    expect(headers['apns-collapse-id']).toBeUndefined();
    const aps = payload.aps as Record<string, unknown>;
    expect(aps.alert).toEqual({ 'title-loc-key': 'HIBOSS_PUSH_TITLE', 'loc-key': locKey });
    expect(aps['thread-id']).toBeUndefined();
  });
});

describe('POST /v1/push validation', () => {
  it.each([
    ['unknown field', { title: 'hi' }],
    ['bad kind', { kind: 'alert' }],
    ['non-base64url ciphertext', { ciphertext: 'abc+def/ghi=' + 'A'.repeat(40) }],
    ['ciphertext over 2048 bytes', { ciphertext: 'A'.repeat(2732) }],
    ['ciphertext shorter than nonce + tag', { ciphertext: 'A'.repeat(36) }],
    ['collapseId over 64 bytes', { collapseId: 'c'.repeat(65) }],
    ['collapseId with a space', { collapseId: 'a b' }],
    ['non-string handle', { handle: 42 }],
  ])('rejects %s with 400 and sends nothing', async (_name, extra) => {
    const fetchMock = mockApns();
    const { handle } = await register();
    const response = await call('POST', '/v1/push', { body: pushBody(handle, extra) });
    expect(response.status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('accepts exactly 2048 ciphertext bytes and a 64-byte collapseId', async () => {
    mockApns();
    const { handle } = await register();
    const body = pushBody(handle, { ciphertext: 'A'.repeat(2730) + 'AA', collapseId: 'c'.repeat(64) });
    expect((await call('POST', '/v1/push', { body })).status).toBe(400);
    const exact = pushBody(handle, { ciphertext: 'A'.repeat(2731), collapseId: 'c'.repeat(64) });
    expect((await call('POST', '/v1/push', { body: exact })).status).toBe(202);
  });
});

describe('POST /v1/push handles', () => {
  it('answers unknown, malformed and deleted handles identically with 410', async () => {
    const fetchMock = mockApns();
    const { handle, deviceSecret } = await register();
    await call('DELETE', '/v1/registrations/self', { secret: deviceSecret });
    const responses = [
      await call('POST', '/v1/push', { body: pushBody('A'.repeat(43)) }),
      await call('POST', '/v1/push', { body: pushBody('') }),
      await call('POST', '/v1/push', { body: pushBody('../../etc') }),
      await call('POST', '/v1/push', { body: pushBody(handle) }),
    ];
    const seen = await Promise.all(responses.map(async (r) => `${r.status} ${await r.text()}`));
    expect(new Set(seen)).toEqual(new Set(['410 {"error":"gone"}']));
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('does not accept the deviceSecret as a push handle', async () => {
    mockApns();
    const { deviceSecret } = await register();
    expect((await call('POST', '/v1/push', { body: pushBody(deviceSecret) })).status).toBe(410);
  });
});

describe('POST /v1/push APNs outcomes', () => {
  it('deletes the registration and answers 410 when APNs answers 410', async () => {
    mockApns(410, 'Unregistered');
    const { handle } = await register();
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(410);
    expect(await countRows('registrations')).toBe(0);
  });

  it('deletes the registration on BadDeviceToken', async () => {
    mockApns(400, 'BadDeviceToken');
    const { handle } = await register();
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(410);
    expect(await countRows('registrations')).toBe(0);
  });

  it('keeps the registration and answers 502 on other APNs failures', async () => {
    mockApns(500, 'InternalServerError');
    const { handle } = await register();
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(502);
    expect(await countRows('registrations')).toBe(1);
  });

  it('answers 503 without calling APNs when the key is not configured', async () => {
    const fetchMock = mockApns();
    const { handle } = await register();
    const response = await call('POST', '/v1/push', {
      body: pushBody(handle),
      env: await relayEnv({ APNS_AUTH_KEY: undefined }),
    });
    expect(response.status).toBe(503);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('refreshes last_used_at on a delivered push', async () => {
    mockApns();
    const { handle } = await register();
    await env.DB.prepare('UPDATE registrations SET last_used_at = 1').run();
    await call('POST', '/v1/push', { body: pushBody(handle) });
    const row = await env.DB.prepare('SELECT last_used_at FROM registrations').first<{ last_used_at: number }>();
    expect(row?.last_used_at).toBeGreaterThan(1);
  });
});

describe('logging', () => {
  it('writes nothing to the console across register, rotate, push, prune and delete', async () => {
    const spies = (['log', 'info', 'warn', 'error', 'debug'] as const).map((m) => vi.spyOn(console, m));
    mockApns();
    const { handle, deviceSecret } = await register();
    await call('PUT', '/v1/registrations/self', {
      secret: deviceSecret,
      body: { apnsToken: TOKEN_A, environment: 'sandbox' },
    });
    await call('POST', '/v1/push', { body: pushBody(handle) });
    await call('POST', '/v1/push', { body: pushBody('A'.repeat(43)) });
    mockApns(410);
    await call('POST', '/v1/push', { body: pushBody(handle) });
    await call('DELETE', '/v1/registrations/self', { secret: deviceSecret });
    for (const spy of spies) expect(spy).not.toHaveBeenCalled();
  });
});
