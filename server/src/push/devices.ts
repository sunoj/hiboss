// Removes a boss-owned push device and every APNs destination referencing it atomically.
// Exports deleteBossDevice; depends on D1 batch transactions and destination cascades.
import type { Env } from '../types';
import { preserveMergedDeliveries } from '../delivery/delete-destination';

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
