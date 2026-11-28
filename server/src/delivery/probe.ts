// Sends explicit destination probes without creating or modifying a message row.
// Exports probeDestination; uses existing APNs adapter and live client checks.
import type { Env } from '../types';
import { sendDevicePush, type PushDevice } from '../push/send';
import { liveDeviceSql } from '../push/devices';
import { jsonObject, type DestinationKind } from './types';
export interface ProbeDestination { boss_id: string; kind: DestinationKind; target: string; client_id: string | null }
export async function probeDestination(env: Env, row: ProbeDestination): Promise<string | null> {
  const config = jsonObject(row.target);
  const device = await env.DB.prepare(`SELECT d.boss_id, d.device_token, d.bundle_id, d.environment,
  d.relay_handle, d.push_key FROM boss_devices d
    LEFT JOIN boss_clients c ON c.id = d.client_id WHERE d.id = ? AND d.boss_id = ? AND d.client_id IS ?
    AND (d.client_id IS NULL OR (c.revoked_at IS NULL AND c.boss_id = d.boss_id)) AND ${liveDeviceSql('d')}`)
    .bind(config.device_id, row.boss_id, row.client_id).first<PushDevice>();
  if (!device) throw new Error('push device unavailable');
  const result = await sendDevicePush(env, device,
    { aps: { alert: { title: 'HiBoss', body: 'Test notification' }, sound: 'default', 'interruption-level': 'active', 'thread-id': 'hiboss-test' } }, '10');
  if (!result.ok) throw new Error('push failed');
  return null;
}
