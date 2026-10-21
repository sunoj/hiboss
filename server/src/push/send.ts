// Selects direct APNs or encrypted relay delivery for every boss push path.
// Exports pushMode and sendDevicePush; depends on APNs, relay encryption and device cleanup.
import { hasApnsConfig, sendPush, type ApnsEnvironment, type ApnsPayload,
  type ApnsPriority, type ApnsSendResult } from '../apns';
import type { Env } from '../types';
import { deleteBossDevice } from './devices';
import { sendRelay, type PushKind } from './relay';

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
  priority: ApnsPriority = '10', kind?: PushKind): Promise<ApnsSendResult> {
  const mode = pushMode(env);
  let result: ApnsSendResult;
  if (mode === 'direct' && !device.relay_handle) {
    result = await sendPush(env, device.device_token, device.environment,
      device.bundle_id, payload, priority);
  } else if (mode === 'relay' && device.relay_handle && device.push_key) {
    const category = payload.aps.category;
    const selected = kind ?? (category === 'HIBOSS_OPTIONS' || category === 'HIBOSS_REQUEST'
      ? 'decision' : payload.messageId ? 'message' : 'system');
    result = await sendRelay(env.PUSH_RELAY_URL || 'https://push.hiboss.org',
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
