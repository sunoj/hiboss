// Verifies shared alert/resolution failure diagnostics without exposing device credentials.
// Uses existing notification fixtures and mocked provider results; no network requests.
import { env } from 'cloudflare:test';
import { afterEach, expect, it, vi } from 'vitest';
import * as apns from '../apns';
import * as relay from './relay';
import { sendDevicePush, sendDeviceResolution, type PushDevice } from './send';

const device: PushDevice = { boss_id: 'boss', device_token: 'abcdef12'.repeat(8),
  bundle_id: 'ai.hiboss.app', environment: 'sandbox' };
const payload: apns.ApnsPayload = { aps: { alert: { title: 'Test', body: 'Test' },
  'interruption-level': 'active', 'thread-id': 'test' } };
const resolution = { id: 'ask', status: 'expired' } as const;
const senders = [
  (target: PushDevice) => sendDevicePush(env, target, payload),
  (target: PushDevice) => sendDeviceResolution(env, target, resolution),
];
afterEach(() => vi.restoreAllMocks());

it.each(senders)('logs failed direct sends with only a token prefix', async send => {
  vi.spyOn(apns, 'hasApnsConfig').mockReturnValue(true);
  vi.spyOn(apns, 'sendPush').mockResolvedValue({ ok: false, prune: false, reason: 'TooManyRequests' });
  vi.spyOn(apns, 'sendApnsRequest').mockResolvedValue({ ok: false, prune: false, reason: 'TooManyRequests' });
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await expect(send(device)).resolves.toMatchObject({ ok: false });
  expect(warn).toHaveBeenCalledExactlyOnceWith('Push failed', { reason: 'TooManyRequests',
    transport: 'direct', environment: 'sandbox', bundle_id: 'ai.hiboss.app', token_prefix: 'abcdef12' });
});

it.each(senders)('logs thrown relay failures with credentials redacted', async send => {
  const target = { ...device, device_token: 'relay:private-handle', relay_handle: 'private-handle',
    push_key: 'private-key' };
  vi.spyOn(apns, 'hasApnsConfig').mockReturnValue(false);
  const error = new Error(`network ${target.device_token} ${target.push_key} ${target.relay_handle}`);
  vi.spyOn(relay, 'sendRelay').mockRejectedValue(error);
  vi.spyOn(relay, 'sendRelayResolution').mockRejectedValue(error);
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await expect(send(target)).rejects.toBe(error);
  expect(warn).toHaveBeenCalledExactlyOnceWith('Push failed', { reason: 'network [redacted] [redacted] [redacted]',
    transport: 'relay', environment: 'sandbox', bundle_id: 'ai.hiboss.app', token_prefix: null });
});

it('logs no full short token and no free-form bundle id', async () => {
  const target = { ...device, device_token: 'abcdef12', bundle_id: 'secret value with spaces' };
  vi.spyOn(apns, 'hasApnsConfig').mockReturnValue(true);
  vi.spyOn(apns, 'sendPush').mockResolvedValue({ ok: false, prune: false, reason: 'TooManyRequests' });
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  await sendDevicePush(env, target, payload);
  expect(warn).toHaveBeenCalledExactlyOnceWith('Push failed', expect.objectContaining({
    bundle_id: '[invalid]', token_prefix: null }));
});

it('logs unavailable transports', async () => {
  vi.spyOn(apns, 'hasApnsConfig').mockReturnValue(false);
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  const off = { ...env, PUSH_RELAY_URL: 'off' };
  await sendDeviceResolution(off, device, resolution);
  await sendDevicePush(off, device, payload);
  expect(warn).toHaveBeenCalledTimes(2);
  expect(warn).toHaveBeenCalledWith('Push failed', expect.objectContaining({
    reason: 'push transport unavailable', transport: 'none' }));
});
