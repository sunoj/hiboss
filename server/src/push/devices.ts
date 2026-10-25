// Removes a boss-owned push device and every APNs destination referencing it atomically.
// Exports deleteBossDevice and liveDeviceSql; depends on D1 batch transactions and destination cascades.
import type { Env } from '../types';
import { preserveMergedDeliveries } from '../delivery/delete-destination';

/** Every push selection's predicate for device `alias`: the token that registered it, and its client, are live. */
export function liveDeviceSql(alias: string): string {
  return `EXISTS (SELECT 1 FROM boss_tokens lt LEFT JOIN boss_clients lc ON lc.id = lt.client_id
    WHERE lt.id = ${alias}.token_id AND lt.boss_id = ${alias}.boss_id AND lt.revoked_at IS NULL
    AND (lt.client_id IS NULL OR lc.revoked_at IS NULL))`;
}

export async function deleteBossDevice(env: Env, bossId: string, token: string): Promise<void> {
  const destinations = await env.DB.prepare(`SELECT id FROM boss_destinations WHERE kind = 'apns'
    AND json_extract(target, '$.device_id') IN
      (SELECT id FROM boss_devices WHERE boss_id = ? AND device_token = ?)`)
    .bind(bossId, token).all<{ id: string }>();
  const preserved: D1PreparedStatement[] = [];
  const removingIds = destinations.results.map(destination => destination.id);
  for (const destination of destinations.results) {
    preserved.push(...await preserveMergedDeliveries(env, destination.id, removingIds));
  }
  await env.DB.batch([
    ...preserved,
    env.DB.prepare(`DELETE FROM boss_destinations WHERE kind = 'apns' AND json_extract(target, '$.device_id') IN
      (SELECT id FROM boss_devices WHERE boss_id = ? AND device_token = ?)`).bind(bossId, token),
    env.DB.prepare('DELETE FROM boss_devices WHERE boss_id = ? AND device_token = ?').bind(bossId, token),
  ]);
}
