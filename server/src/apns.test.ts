// Unit tests for APNs provider auth and fetch delivery.
// Covers missing config, successful sends, and prune signals.
// Depends on Workers WebCrypto and mocked fetch.

import { afterEach, describe, expect, it, vi } from 'vitest';
import { hasApnsConfig, sendPush, type ApnsPayload } from './apns';
import type { Env } from './types';

const payload: ApnsPayload = {
  aps: {
    alert: { title: 'HiBoss', body: 'Hello' },
    sound: 'default',
    'interruption-level': 'active',
    'thread-id': 'boss-1',
  },
  messageId: 'msg-1',
};

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('APNs sender', () => {
  it('reports missing config without calling fetch', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    const result = await sendPush({} as Env, 'abcd', 'sandbox', 'com.hiboss.app', payload);

    expect(result).toEqual({ ok: false, prune: false, reason: 'missing APNs config' });
    expect(fetchMock).not.toHaveBeenCalled();
    expect(hasApnsConfig({} as Env)).toBe(false);
  });

  it('sends an alert push to the sandbox APNs endpoint', async () => {
    const authKey = await createPrivateKeyPem();
    const fetchMock = vi.fn<typeof fetch>(
      async () => new Response(null, { status: 200 }),
    );
    vi.stubGlobal('fetch', fetchMock);

    const result = await sendPush(apnsEnv(authKey), 'abcdef', 'sandbox', 'com.hiboss.app', payload);

    expect(result).toEqual({ ok: true, prune: false });
    expect(fetchMock).toHaveBeenCalledOnce();
    const [url, init] = fetchMock.mock.calls[0] as Parameters<typeof fetch>;
    expect(url).toBe('https://api.sandbox.push.apple.com/3/device/abcdef');
    const headers = init?.headers as Record<string, string>;
    expect(headers['apns-topic']).toBe('com.hiboss.app');
    expect(headers['apns-push-type']).toBe('alert');
    expect(headers.authorization.startsWith('bearer ')).toBe(true);
    expect(init?.body).toBe(JSON.stringify(payload));
  });

  it('returns prune for BadDeviceToken responses', async () => {
    const authKey = await createPrivateKeyPem();
    const fetchMock = vi.fn<typeof fetch>(
      async () => Response.json({ reason: 'BadDeviceToken' }, { status: 400 }),
    );
    vi.stubGlobal('fetch', fetchMock);

    const result = await sendPush(apnsEnv(authKey), 'abcdef', 'production', 'com.hiboss.app', payload);

    expect(result).toEqual({ ok: false, prune: true, reason: 'BadDeviceToken' });
    expect(fetchMock.mock.calls[0][0]).toBe('https://api.push.apple.com/3/device/abcdef');
  });
});

function apnsEnv(authKey: string): Env {
  return {
    DB: undefined as never,
    ATTACHMENTS: undefined as never,
    APNS_KEY_ID: 'KEY1234567',
    APNS_TEAM_ID: 'TEAM123456',
    APNS_AUTH_KEY: authKey,
  };
}

async function createPrivateKeyPem(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  );
  const pkcs8 = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  return `-----BEGIN PRIVATE KEY-----\n${base64Bytes(new Uint8Array(pkcs8))}\n-----END PRIVATE KEY-----`;
}

function base64Bytes(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
