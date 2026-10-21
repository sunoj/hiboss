// Scheduled cleanup: registrations unused for 30 days and expired rate counters.

import { DAY_MS } from './limits';

export const UNUSED_RETENTION_MS = 30 * DAY_MS;

export async function purge(db: D1Database, now: number): Promise<void> {
  await db.batch([
    db.prepare('DELETE FROM registrations WHERE last_used_at < ?').bind(now - UNUSED_RETENTION_MS),
    db.prepare('DELETE FROM rate_counters WHERE expires_at <= ?').bind(now),
  ]);
}
