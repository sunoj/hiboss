// Resolves boss-owned destinations, priority thresholds, and quiet hours.
// Exports the D1 resolver and pure eligibility helpers; depends on quiet-hours utilities.
import type { Env, Priority } from '../types';
import { getQuietHoursEnd, isInQuietHours } from '../routes/quiet-hours';
import { jsonObject, PRIORITY_RANK } from './types';
import { liveDeviceSql } from '../push/devices';
import type { DestinationMessage, DestinationRow, ResolvedDestination } from './types';

export function eligibleDestination(row: DestinationRow, message: DestinationMessage): boolean {
  return message.direction === 'agent_to_boss' && row.enabled === 1
    && PRIORITY_RANK[row.min_priority] <= PRIORITY_RANK[message.priority];
}

export function destinationQuietEnd(row: DestinationRow, priority: Priority, now: Date): string | null {
  if (priority === 'high' || priority === 'critical') return null;
  if (!row.honours_quiet_hours || row.quiet_enabled === 0) return null;
  if (!row.quiet_end || !isInQuietHours(row.quiet_start, row.quiet_end, row.timezone, now)) return null;
  return getQuietHoursEnd(row.quiet_end, row.timezone ?? 'UTC', now).toISOString();
}

export async function resolveDestinations(env: Env, message: DestinationMessage, now = new Date()): Promise<ResolvedDestination[]> {
  if (message.direction !== 'agent_to_boss') return [];
  const rows = await env.DB.prepare(`SELECT d.*, b.preferences,
    COALESCE(json_extract(b.preferences, '$.quiet_hours_start'), json_extract(b.preferences, '$.quiet_hours.start')) AS quiet_start,
    COALESCE(json_extract(b.preferences, '$.quiet_hours_end'), json_extract(b.preferences, '$.quiet_hours.end')) AS quiet_end,
    COALESCE(json_extract(b.preferences, '$.quiet_hours.timezone'), json_extract(b.preferences, '$.timezone')) AS timezone,
    json_extract(b.preferences, '$.quiet_hours.enabled') AS quiet_enabled
    FROM boss_destinations d JOIN bosses b ON b.id = d.boss_id
    LEFT JOIN boss_clients c ON c.id = d.client_id
    WHERE b.archived_at IS NULL AND d.enabled = 1 AND (d.client_id IS NULL OR (c.revoked_at IS NULL AND c.boss_id = d.boss_id))
    AND (b.role = 'admin' OR EXISTS (SELECT 1 FROM boss_agent_access a WHERE a.boss_id = b.id AND a.agent_id = ?))
    AND (d.kind != 'apns' OR EXISTS (SELECT 1 FROM boss_devices dev
      WHERE dev.id = json_extract(d.target, '$.device_id') AND dev.boss_id = d.boss_id
      AND dev.client_id IS d.client_id AND ${liveDeviceSql('dev')})) ORDER BY d.id`).bind(message.agent_id).all<DestinationRow>();
  const resolved: ResolvedDestination[] = [];
  for (const row of rows.results) {
    if (!eligibleDestination(row, message)) continue;
    resolved.push({ ...row, config: jsonObject(row.target), nextAttemptAt: destinationQuietEnd(row, message.priority, now) });
  }
  return resolved;
}
