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

export async function sendDevicePush(env: Env, device: PushDevice, payload: ApnsPayload,
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
    return { ok: false, prune: false, reason: 'push transport unavailable' };
  }
  if (result.prune) await deleteBossDevice(env, device.boss_id, device.device_token);
  return result;
}

const RESOLUTION_TIMEOUT_MS = 5_000;

function relayUrl(env: Env): string {
  return env.PUSH_RELAY_URL || 'https://push.hiboss.org';
}

/** Silent push that tells one device an ask closed; prunes a dead token as alerts do. */
export async function sendDeviceResolution(env: Env, device: PushDevice,
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
    return { ok: false, prune: false, reason: 'push transport unavailable' };
  }
  if (result.prune) await deleteBossDevice(env, device.boss_id, device.device_token);
  return result;
}
