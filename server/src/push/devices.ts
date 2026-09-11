// Removes a boss-owned push device and every APNs destination referencing it atomically.
// Exports deleteBossDevice; depends on D1 batch transactions and destination cascades.
import type { Env } from '../types';

export async function deleteBossDevice(env: Env, bossId: string, token: string): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(`DELETE FROM boss_destinations WHERE kind = 'apns' AND json_extract(target, '$.device_id') IN
      (SELECT id FROM boss_devices WHERE boss_id = ? AND device_token = ?)`).bind(bossId, token),
    env.DB.prepare('DELETE FROM boss_devices WHERE boss_id = ? AND device_token = ?').bind(bossId, token),
  ]);
}
