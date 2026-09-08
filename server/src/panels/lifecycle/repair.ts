// Periodically recovers durable pending controls after alarm retry exhaustion.
// Exports repairPanelRooms for the Worker scheduled entry point.
// Dependencies: D1 recipient discovery and internal PanelRoom repair requests.

import type { Env } from '../../types';
const PAGE_SIZE = 100;
const PARALLEL_ROOMS = 10;

export async function repairPanelRooms(env: Env): Promise<void> {
  if (!env.PANEL_ROOM) return;
  const namespace = env.PANEL_ROOM;
  let cursor = '';
  while (true) {
    const page = await env.DB.prepare('SELECT DISTINCT target_boss_id FROM panels WHERE target_boss_id > ? ORDER BY target_boss_id LIMIT ?')
      .bind(cursor, PAGE_SIZE).all<{ target_boss_id: string }>();
    const rows = page.results;
    for (let offset = 0; offset < rows.length; offset += PARALLEL_ROOMS) {
      const outcomes = await Promise.allSettled(rows.slice(offset, offset + PARALLEL_ROOMS).map(async row => {
        const response = await namespace.get(namespace.idFromName(row.target_boss_id)).fetch('https://panel-room.internal/__repair', { method: 'POST' });
        if (!response.ok) throw new Error(`Panel repair failed: ${response.status}`);
      }));
      for (const outcome of outcomes) if (outcome.status === 'rejected') console.error('Panel repair will retry on the next sweep');
    }
    if (rows.length < PAGE_SIZE) return;
    cursor = rows[rows.length - 1].target_boss_id;
  }
}
