// Selects direct APNs or encrypted relay delivery for every boss push path.
// Exports pushMode, sendDevicePush and sendDeviceResolution; depends on APNs, relay and device cleanup.
import { hasApnsConfig, sendApnsRequest, sendPush, type ApnsEnvironment, type ApnsPayload,
  type ApnsPriority, type ApnsSendResult } from '../apns';
import type { Env } from '../types';
import { deleteBossDevice } from './devices';
import { sendRelay, sendRelayResolution, type AlertKind, type Resolution } from './relay';

export interface PushDevice {
  boss_id: string;
  device_token: string;
  bundle_id: string;
  environment: ApnsEnvironment;
  relay_handle?: string | null;
  push_key?: string | null;
}

export function pushMode(env: Env): 'direct' | 'relay' | 'none' {
  if (hasApnsConfig(env)) return 'direct';
  return env.PUSH_RELAY_URL?.trim().toLowerCase() === 'off' ? 'none' : 'relay';
}

async function deliverDevicePush(env: Env, device: PushDevice, payload: ApnsPayload,
  priority: ApnsPriority = '10', kind?: AlertKind): Promise<ApnsSendResult> {
  const mode = pushMode(env);
  let result: ApnsSendResult;
  if (mode === 'direct' && !device.relay_handle) {
    result = await sendPush(env, device.device_token, device.environment,
      device.bundle_id, payload, priority);
  } else if (mode === 'relay' && device.relay_handle && device.push_key) {
    const category = payload.aps.category;
    const selected = kind ?? (category === 'HIBOSS_OPTIONS' || category === 'HIBOSS_REQUEST'
      ? 'decision' : payload.messageId ? 'message' : 'system');
    result = await sendRelay(relayUrl(env),
      device.relay_handle, device.push_key, payload, selected, priority);
  } else if ((mode === 'direct' && device.relay_handle)
    || (mode === 'relay' && !device.relay_handle)) {
    result = { ok: false, prune: true, reason: 'push transport mismatch' };
  } else {
    result = { ok: false, prune: false, reason: 'push transport unavailable' };
  }
  return result;
}

const RESOLUTION_TIMEOUT_MS = 5_000;

function relayUrl(env: Env): string {
  return env.PUSH_RELAY_URL || 'https://push.hiboss.org';
}

/** Silent push that tells one device an ask closed; prunes a dead token as alerts do. */
async function deliverDeviceResolution(env: Env, device: PushDevice,
  resolution: Resolution): Promise<ApnsSendResult> {
  const mode = pushMode(env);
  const signal = AbortSignal.timeout(RESOLUTION_TIMEOUT_MS);
  let result: ApnsSendResult;
  if (mode === 'direct' && !device.relay_handle) {
    result = await sendApnsRequest(env, { token: device.device_token, environment: device.environment,
      topic: device.bundle_id, pushType: 'background', priority: '5', signal,
      body: JSON.stringify({ aps: { 'content-available': 1 },
        hiboss: { resolved: { id: resolution.id, status: resolution.status } } }) });
  } else if (mode === 'relay' && device.relay_handle && device.push_key) {
    result = await sendRelayResolution(relayUrl(env), device.relay_handle, device.push_key, resolution, signal);
  } else {
    result = { ok: false, prune: false, reason: 'push transport unavailable' };
  }
  return result;
}

/** Observe failures once at the shared boundary, preserving best-effort caller behavior. */
async function observePush(env: Env, device: PushDevice,
  send: () => Promise<ApnsSendResult>): Promise<ApnsSendResult> {
  let result: ApnsSendResult;
  try {
    result = await send();
  } catch (error) {
    warnPushFailure(env, device, error);
    throw error;
  }
  if (!result.ok) warnPushFailure(env, device, result.reason);
  if (result.prune) {
    try {
      await deleteBossDevice(env, device.boss_id, device.device_token, safeReason(device, result.reason));
    } catch (error) {
      warnPushFailure(env, device, error);
      throw error;
    }
  }
  return result;
}

function safeReason(device: PushDevice, error: unknown): string {
  let reason = error instanceof Error ? error.message : String(error);
  for (const secret of [device.device_token, device.push_key, device.relay_handle]) {
    if (secret) reason = reason.split(secret).join('[redacted]');
  }
  return reason.replace(/[0-9a-fA-F]{9,}/g, '[redacted]');
}

function warnPushFailure(env: Env, device: PushDevice, error: unknown): void {
  console.warn('Push failed', { reason: safeReason(device, error), transport: pushMode(env),
    environment: device.environment, bundle_id: device.bundle_id,
    token_prefix: /^[0-9a-fA-F]+$/.test(device.device_token) ? device.device_token.slice(0, 8) : null });
}

export async function sendDevicePush(env: Env, device: PushDevice, payload: ApnsPayload,
  priority: ApnsPriority = '10', kind?: AlertKind): Promise<ApnsSendResult> {
  return observePush(env, device, () => deliverDevicePush(env, device, payload, priority, kind));
}

export async function sendDeviceResolution(env: Env, device: PushDevice,
  resolution: Resolution): Promise<ApnsSendResult> {
  return observePush(env, device, () => deliverDeviceResolution(env, device, resolution));
}
