// Resolves boss-owned destinations, priority thresholds, quiet hours, and thread routes.
// Exports the D1 resolver and pure eligibility helpers; depends on quiet-hours utilities.
import type { Env, Priority } from '../types';
import { getQuietHoursEnd, isInQuietHours } from '../routes/quiet-hours';
import { jsonObject, PRIORITY_RANK } from './types';
import type { DestinationMessage, DestinationRow, ResolvedDestination, RouteRow } from './types';

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
  const rows = await env.DB.prepare(`SELECT d.*, p.credentials, b.preferences,
    COALESCE(json_extract(b.preferences, '$.quiet_hours_start'), json_extract(b.preferences, '$.quiet_hours.start')) AS quiet_start,
    COALESCE(json_extract(b.preferences, '$.quiet_hours_end'), json_extract(b.preferences, '$.quiet_hours.end')) AS quiet_end,
    COALESCE(json_extract(b.preferences, '$.quiet_hours.timezone'), json_extract(b.preferences, '$.timezone')) AS timezone,
    json_extract(b.preferences, '$.quiet_hours.enabled') AS quiet_enabled
    FROM boss_destinations d JOIN bosses b ON b.id = d.boss_id
    LEFT JOIN channel_providers p ON p.id = d.provider_id
    LEFT JOIN boss_clients c ON c.id = d.client_id
    WHERE d.enabled = 1 AND (d.client_id IS NULL OR (c.revoked_at IS NULL AND c.boss_id = d.boss_id))
    AND (b.role = 'admin' OR EXISTS (SELECT 1 FROM boss_agent_access a WHERE a.boss_id = b.id AND a.agent_id = ?))
    AND (d.kind != 'apns' OR EXISTS (SELECT 1 FROM boss_devices dev
      WHERE dev.id = json_extract(d.target, '$.device_id') AND dev.boss_id = d.boss_id
      AND dev.client_id IS d.client_id)) ORDER BY d.id`).bind(message.agent_id).all<DestinationRow>();
  const scope = await resolveScope(env, message);
  const resolved: ResolvedDestination[] = [];
  for (const row of rows.results) {
    if (!eligibleDestination(row, message)) continue;
    const route = await lookupRoute(env, row, message, scope);
    resolved.push({ ...row, config: routeConfig(row, route), nextAttemptAt: destinationQuietEnd(row, message.priority, now) });
  }
  return resolved;
}

async function resolveScope(env: Env, message: DestinationMessage): Promise<string | null> {
  if (message.project) {
    const row = await env.DB.prepare(`SELECT id FROM projects WHERE slug = ? OR id =
      (SELECT project_id FROM project_aliases WHERE alias = ?)`)
      .bind(message.project, message.project).first<{ id: string }>();
    return row?.id ?? null;
  }
  return env.DB.prepare('SELECT project_id FROM sessions WHERE id = ? AND agent_id = ?')
    .bind(message.session_id, message.agent_id).first<string>('project_id');
}

async function lookupRoute(env: Env, row: DestinationRow, message: DestinationMessage, projectId: string | null): Promise<RouteRow | null> {
  return env.DB.prepare(`SELECT external_channel_id, external_thread_id FROM destination_routes
    WHERE destination_id = ? AND ((session_id = ? AND (project_id IS NULL OR project_id = ?))
      OR (session_id IS NULL AND (project_id = ? OR project_id IS NULL)))
    ORDER BY (session_id IS NOT NULL) DESC, (project_id IS NOT NULL) DESC, id LIMIT 1`)
    .bind(row.id, message.session_id, projectId, projectId).first<RouteRow>();
}

function routeConfig(row: DestinationRow, route: RouteRow | null): Record<string, unknown> {
  const config = { ...jsonObject(row.target), ...jsonObject(row.credentials) };
  if (row.kind === 'telegram_chat') {
    if (route?.external_channel_id) config.chat_id = route.external_channel_id;
    if (route?.external_thread_id) config.message_thread_id = Number(route.external_thread_id);
  }
  if (row.kind === 'discord_channel') {
    if (config.thread_id) config.channel_id = config.thread_id;
    if (route?.external_channel_id) config.channel_id = route.external_channel_id;
    if (route?.external_thread_id) {
      config.channel_id = route.external_thread_id;
      config.thread_id = route.external_thread_id;
    }
  }
  return config;
}
