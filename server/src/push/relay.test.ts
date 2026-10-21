// Regression coverage for transport selection, encrypted payloads and relay cleanup.
// Uses real WebCrypto and D1 with mocked outbound HTTP and captured logs.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { sendDevicePush, pushMode, type PushDevice } from './send';
import { sendRelay } from './relay';
import type { ApnsPayload } from '../apns';

const handle = 'a'.repeat(42) + 'A';
const pushKey = 'b'.repeat(42) + 'A';
const token = 'relay:' + handle;
const bearer = 'relay-test-boss-token';
const device: PushDevice = { boss_id: 'relay-boss', device_token: token, bundle_id: 'ai.hiboss.app',
  environment: 'production', relay_handle: handle, push_key: pushKey };
const payload: ApnsPayload = { aps: { alert: { title: 'Title', body: 'Body' },
  'interruption-level': 'active', 'thread-id': 'boss', category: 'HIBOSS_OPTIONS' },
  messageId: 'message-1', options: ['Yes', 'No'] };
beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Relay Boss', 'admin', bearer, device.boss_id);
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

it('selects direct before relay, defaults to relay, and permits disabling it', () => {
  expect(pushMode({ ...env, APNS_KEY_ID: '', APNS_TEAM_ID: '', APNS_AUTH_KEY: '' })).toBe('relay');
  expect(pushMode({ ...env, PUSH_RELAY_URL: 'off' })).toBe('none');
  expect(pushMode({ ...env, PUSH_RELAY_URL: 'off', APNS_KEY_ID: 'id', APNS_TEAM_ID: 'team',
    APNS_AUTH_KEY: 'key' })).toBe('direct');
});

function decode(value: string): Uint8Array<ArrayBuffer> {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from(atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, '=')), c => c.charCodeAt(0));
}

it.each([false, true])('encrypts bounded userInfo with authenticated kind (large=%s)', async large => {
  let wire: { ciphertext: string; kind: string; handle: string } | undefined;
  vi.stubGlobal('fetch', vi.fn(async (_url, init) => {
    wire = JSON.parse(init.body);
    return new Response(null, { status: 202 });
  }));
  const original = structuredClone(payload);
  if (large) { original.message = { body: '秘密'.repeat(4000) }; original.aps.alert.body = '🙂'.repeat(4000); }
  expect((await sendRelay('https://relay.test', handle, pushKey, original, 'decision')).ok).toBe(true);
  expect(wire?.kind).toBe('decision');
  const bytes = decode(wire!.ciphertext);
  expect(bytes.length).toBeLessThanOrEqual(2048);
  const key = await crypto.subtle.importKey('raw', decode(pushKey), 'AES-GCM', false, ['decrypt']);
  const algorithm = { name: 'AES-GCM', iv: bytes.slice(0, 12),
    additionalData: new TextEncoder().encode('hiboss-push-v1|decision') };
  const plain = await crypto.subtle.decrypt(algorithm, key, bytes.slice(12));
  const result = JSON.parse(new TextDecoder().decode(plain));
  expect(result.messageId).toBe(payload.messageId);
  expect(result.options).toEqual(payload.options);
  expect(result.aps.category).toBe('HIBOSS_OPTIONS');
  if (!large) expect(result).toEqual(payload);
  else expect(result.aps.alert.body.length).toBeLessThan(original.aps.alert.body.length);
  await expect(crypto.subtle.decrypt({ ...algorithm,
    additionalData: new TextEncoder().encode('hiboss-push-v1|message') },
    key, bytes.slice(12))).rejects.toThrow();
});

async function register(extra: Record<string, unknown> = {}): Promise<Response> {
  return SELF.fetch('https://test/api/boss/devices', { method: 'POST',
    headers: { Authorization: `Bearer ${bearer}`, 'content-type': 'application/json' },
    body: JSON.stringify({ relayHandle: handle, pushKey, environment: 'production', platform: 'ios',
      bundleId: device.bundle_id, ...extra }) });
}

it('registers relay credentials as given and reports push mode on the connect response', async () => {
  expect((await register()).status).toBe(200);
  const row = await env.DB.prepare('SELECT relay_handle, push_key FROM boss_devices WHERE device_token = ?')
    .bind(token).first();
  expect(row).toEqual({ relay_handle: handle, push_key: pushKey });
  const me = await SELF.fetch('https://test/api/boss/me', { headers: { Authorization: `Bearer ${bearer}` } });
  expect(await me.json()).toMatchObject({ pushMode: 'relay' });
});

it.each([{ token: 'abcd' }, { pushKey: 'bad' }, { relayHandle: 'bad' }, { pushKey: null },
  { environment: 'dev' }, { platform: 'web' }, { bundleId: '' }])(
  'rejects invalid relay registration %j', async extra => {
  expect((await register(extra)).status).toBe(400);
});

it('removes a device after relay 410 and never logs credentials or ciphertext', async () => {
  expect((await register()).status).toBe(200);
  const logs = [vi.spyOn(console, 'log'), vi.spyOn(console, 'warn'), vi.spyOn(console, 'error')];
  const fetch = vi.fn(async (_url: RequestInfo | URL, _init?: RequestInit) =>
    new Response(handle + pushKey, { status: 410 }));
  vi.stubGlobal('fetch', fetch);
  const result = await sendDevicePush({ ...env, APNS_KEY_ID: '', APNS_TEAM_ID: '', APNS_AUTH_KEY: '' },
    device, payload);
  expect(result).toMatchObject({ ok: false, prune: true, reason: 'relay 410' });
  const row = await env.DB.prepare('SELECT id FROM boss_devices WHERE device_token = ?').bind(token).first();
  expect(row).toBeNull();
  const ciphertext = JSON.parse(fetch.mock.calls[0]?.[1]?.body as string).ciphertext;
  const captured = JSON.stringify(logs.map(log => log.mock.calls));
  for (const secret of [handle, pushKey, ciphertext]) expect(captured).not.toContain(secret);
});
