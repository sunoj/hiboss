// Boss notification preference schema, validation, and delivery resolution.
// Exports typed preferences, defaults, validator, and routing lookup helpers.
// Depends on shared Env, Channel, and Priority domain types.

import type { Channel, Env, Priority } from '../types';

export type BossRoutingChannel = 'discord' | 'telegram' | 'api';
export type BossPriority = 'critical' | 'high' | 'normal' | 'low';

export interface BossQuietHours {
  enabled: boolean;
  start: string;
  end: string;
  timezone: string;
  days: number[];
  critical_bypass: boolean;
}

export type BossRouting = Partial<Record<BossPriority, BossRoutingChannel[]>>;

export interface BossPreferences {
  routing?: BossRouting;
  quiet_hours?: BossQuietHours | null;
}

export type BossPreferencesValidationResult =
  | { ok: true; value: BossPreferences }
  | { ok: false; error: string };

export type BossRoutingResolution =
  | { kind: 'not_configured' }
  | { kind: 'muted' }
  | { kind: 'channels'; channels: Channel[] };

const VALID_PRIORITIES: BossPriority[] = ['critical', 'high', 'normal', 'low'];
const VALID_CHANNELS: BossRoutingChannel[] = ['discord', 'telegram', 'api'];
const TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;

export const DEFAULT_BOSS_PREFERENCES: BossPreferences = { quiet_hours: null };

export function validateBossPreferences(prefs: Record<string, unknown>): BossPreferencesValidationResult {
  if ('routing' in prefs) {
    const routingError = validateRouting(prefs.routing);
    if (routingError) return { ok: false, error: routingError };
  }
  if ('quiet_hours' in prefs) {
    const quietHoursError = validateQuietHours(prefs.quiet_hours);
    if (quietHoursError) return { ok: false, error: quietHoursError };
  }
  return { ok: true, value: prefs as BossPreferences };
}

export function parseBossPreferences(value: string | null): BossPreferences | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(value) as unknown;
    if (!isRecord(parsed)) return null;
    const result = validateBossPreferences(parsed);
    return result.ok ? result.value : null;
  } catch {
    return null;
  }
}

export async function resolveBossRoutingChannels(
  env: Env,
  agentId: string,
  priority: Priority,
): Promise<BossRoutingResolution> {
  const rows = await env.DB
    .prepare(
      `SELECT preferences FROM bosses
       WHERE preferences IS NOT NULL
         AND (
           role = 'admin'
           OR agent_id = ?
           OR id IN (SELECT boss_id FROM boss_agent_access WHERE agent_id = ?)
         )`
    )
    .bind(agentId, agentId)
    .all<{ preferences: string | null }>();

  let hasPriorityRouting = false;
  const channels = new Set<Channel>();
  for (const row of rows.results ?? []) {
    const routing = parseBossPreferences(row.preferences)?.routing;
    if (!routing || !hasOwn(routing, priority)) continue;
    hasPriorityRouting = true;
    // Across multiple bosses, present priority keys opt into routing for that priority:
    // channel arrays union, empty arrays add nothing, and absent keys never force legacy fallback.
    for (const channel of routing[priority] ?? []) {
      channels.add(channel);
    }
  }
  if (!hasPriorityRouting) return { kind: 'not_configured' };
  return channels.size > 0 ? { kind: 'channels', channels: Array.from(channels) } : { kind: 'muted' };
}

function validateRouting(value: unknown): string | null {
  if (!isRecord(value)) return 'routing must be an object';
  for (const [priority, channels] of Object.entries(value)) {
    if (!VALID_PRIORITIES.includes(priority as BossPriority)) {
      return 'routing keys must be critical, high, normal, or low';
    }
    if (!Array.isArray(channels)) {
      return `routing.${priority} must be an array`;
    }
    const valid = channels.every((channel) =>
      typeof channel === 'string' && VALID_CHANNELS.includes(channel as BossRoutingChannel)
    );
    if (!valid) return `routing.${priority} channels must be discord, telegram, or api`;
  }
  return null;
}

function validateQuietHours(value: unknown): string | null {
  if (value === null) return null;
  if (!isRecord(value)) return 'quiet_hours must be an object or null';
  if (typeof value.enabled !== 'boolean') return 'quiet_hours.enabled must be a boolean';
  if (typeof value.start !== 'string' || !TIME_PATTERN.test(value.start)) {
    return 'quiet_hours.start must be HH:MM';
  }
  if (typeof value.end !== 'string' || !TIME_PATTERN.test(value.end)) {
    return 'quiet_hours.end must be HH:MM';
  }
  if (typeof value.timezone !== 'string' || !isValidTimeZone(value.timezone)) {
    return 'quiet_hours.timezone must be a valid IANA timezone';
  }
  if (!Array.isArray(value.days) || !value.days.every(isValidDay)) {
    return 'quiet_hours.days must be an array of numbers from 0 to 6';
  }
  if (typeof value.critical_bypass !== 'boolean') {
    return 'quiet_hours.critical_bypass must be a boolean';
  }
  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function hasOwn<T extends object>(value: T, key: PropertyKey): boolean {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function isValidDay(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= 6;
}

function isValidTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}
