// Regression coverage for transport selection, encrypted payloads and relay cleanup.
// Uses real WebCrypto and D1 with mocked outbound HTTP and captured logs.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import { sendDevicePush, pushMode, type PushDevice } from './send';
import { sendRelay } from './relay';
import type { ApnsPayload } from '../apns';
import type { MessageRow, Priority } from '../types';
import { prepareBossPush } from './boss-payload';
import { joinRequestPayload } from '../devices/notify-push';

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


it('uses the default relay URL when the setting is empty', async () => {
  const fetch = vi.fn<typeof globalThis.fetch>(async () => new Response(null, { status: 202 }));
  vi.stubGlobal('fetch', fetch);
  await sendDevicePush({ ...env, PUSH_RELAY_URL: '', APNS_KEY_ID: '', APNS_TEAM_ID: '',
    APNS_AUTH_KEY: '' }, device, payload);
  expect(fetch.mock.calls[0]?.[0]).toBe('https://push.hiboss.org/v1/push');
});

it('lets the owner delete their relay device through the API', async () => {
  expect((await register()).status).toBe(200);
  const response = await SELF.fetch(`https://test/api/boss/devices/${token}`, {
    method: 'DELETE', headers: { Authorization: `Bearer ${bearer}` },
  });
  expect(response.status).toBe(200);
  expect(await env.DB.prepare('SELECT id FROM boss_devices WHERE device_token = ?')
    .bind(token).first()).toBeNull();
});


it.each([
  ['normal', false, false, 5, 'passive', false],
  ['high', false, false, 10, 'active', true],
  ['critical', false, false, 10, 'time-sensitive', true],
  ['normal', true, false, 10, 'active', true],
  ['normal', true, true, 10, 'active', true],
  ['high', true, true, 10, 'active', true],
  ['critical', true, true, 10, 'time-sensitive', true],
  ['join', false, false, 10, 'time-sensitive', true],
] as const)('matches direct APNs delivery levels for %s (decision=%s, private=%s)',
  async (tier, decision, privatePush, priority, interruption, sound) => {
  const message = { id: 'level-message', agent_id: 'test-agent-id', direction: 'agent_to_boss',
    mode: 'async', body: 'Body', priority: tier as Priority, metadata: decision
      ? JSON.stringify({ options: ['Yes', 'No'] }) : null } as MessageRow;
  const prepared = tier === 'join' ? { payload: joinRequestPayload({ requestId: 'join-1',
    deviceLabel: 'Phone', profiles: [], inviterLabel: null, verificationCode: null,
    existingDevice: false }), apnsPriority: '10' as const }
    : prepareBossPush(message, 'Agent', null, device.boss_id,
      JSON.stringify({ private_push: privatePush }));
  expect(prepared).not.toBeNull();
  if (!prepared) throw new Error('missing prepared payload');
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const pkcs8 = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  const authKey = btoa(String.fromCharCode(...new Uint8Array(pkcs8)));
  const fetch = vi.fn<typeof globalThis.fetch>(async () => new Response(null, { status: 202 }));
  vi.stubGlobal('fetch', fetch);
  await sendDevicePush({ ...env, APNS_KEY_ID: 'level-key', APNS_TEAM_ID: 'level-team', APNS_AUTH_KEY: authKey },
    { ...device, device_token: 'abcd', relay_handle: null, push_key: null },
    prepared.payload, prepared.apnsPriority);
  await sendDevicePush({ ...env, APNS_KEY_ID: '', APNS_TEAM_ID: '', APNS_AUTH_KEY: '' },
    device, prepared.payload, prepared.apnsPriority);
  const direct = fetch.mock.calls[0]?.[1];
  const aps = JSON.parse(direct?.body as string).aps;
  const relay = JSON.parse(fetch.mock.calls[1]?.[1]?.body as string);
  expect(relay).toMatchObject({ priority, interruption, sound });
  expect(relay.priority).toBe(Number((direct?.headers as Record<string, string>)['apns-priority']));
  expect(relay.interruption).toBe(aps['interruption-level']);
  expect(relay.sound).toBe(aps.sound === 'default');
});
