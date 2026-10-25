// APNs prompt to admin bosses' iPhones when a device asks to join.
// Exports pushJoinRequest and joinRequestPayload; best effort per device, prunes dead tokens.
// Depends on the shared APNs sender and boss_devices registrations.
import type { Env } from '../types';
import { pushMode, sendDevicePush, type PushDevice } from '../push/send';
import { liveDeviceSql } from '../push/devices';
import type { ApnsPayload } from '../apns';

export interface JoinNotice {
  requestId: string;
  deviceLabel: string;
  profiles: Array<{ profile: string; name: string }>;
  inviterLabel: string | null;
  verificationCode: string | null;
  existingDevice: boolean;
}

export const JOIN_REQUEST_CATEGORY = 'HIBOSS_JOIN_REQUEST';

export function joinRequestPayload(notice: JoinNotice): ApnsPayload {
  const profiles = notice.profiles.map(p => p.profile).join(', ');
  const code = notice.verificationCode ? ` · code ${notice.verificationCode}` : '';
  return {
    aps: {
      alert: {
        title: 'New device wants to join',
        subtitle: notice.existingDevice ? 'Adds profiles to an enrolled device'
          : notice.inviterLabel ? `Invited from ${notice.inviterLabel}` : undefined,
        body: `${notice.deviceLabel} (${profiles})${code}`,
      },
      sound: 'default',
      'interruption-level': 'time-sensitive',
      'thread-id': 'hiboss-join-requests',
      category: JOIN_REQUEST_CATEGORY,
    },
    join_request_id: notice.requestId,
  };
}

export async function pushJoinRequest(env: Env, notice: JoinNotice): Promise<void> {
  if (pushMode(env) === 'none') return;
  const devices = await env.DB.prepare(`SELECT d.boss_id, d.device_token, d.bundle_id, d.environment,
    d.relay_handle, d.push_key FROM boss_devices d
    JOIN bosses b ON b.id = d.boss_id WHERE b.role = 'admin' AND b.archived_at IS NULL AND ${liveDeviceSql('d')}`)
    .all<PushDevice>();
  const payload = joinRequestPayload(notice);
  for (const device of devices.results ?? []) {
    try {
      await sendDevicePush(env, device, payload, '10');
    } catch {
      // Best effort per device: one failed push must not block the others.
    }
  }
}
