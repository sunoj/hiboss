// Quiet-hours helpers for boss delivery deferral and timezone-aware scheduling.
// Exports pure window calculations plus agent-level preference lookup from D1.
// Depends on Intl.DateTimeFormat and the shared Env binding type.

import type { Env } from '../types';

interface LocalTime {
  hours: number;
  minutes: number;
}

interface ZonedDateParts {
  year: number;
  month: number;
  day: number;
  hours: number;
  minutes: number;
  seconds: number;
}

interface QuietHoursRow {
  quiet_start: string | null;
  quiet_end: string | null;
  timezone: string | null;
  // json_extract returns 1/0 for a JSON boolean, or null when the key is absent.
  enabled: number | null;
}

const TIME_PATTERN = /^([01]\d|2[0-3]):([0-5]\d)$/;
const DEFAULT_TIME_ZONE = 'UTC';
const formatterCache = new Map<string, Intl.DateTimeFormat>();

export function isInQuietHours(
  quietStart: string | null,
  quietEnd: string | null,
  timezone: string | null,
  now: Date = new Date(),
): boolean {
  const start = parseLocalTime(quietStart);
  const end = parseLocalTime(quietEnd);
  if (!start || !end) return false;

  const localNow = getZonedDateParts(now, resolveTimeZone(timezone));
  const currentMinutes = localNow.hours * 60 + localNow.minutes;
  const startMinutes = start.hours * 60 + start.minutes;
  const endMinutes = end.hours * 60 + end.minutes;

  if (startMinutes === endMinutes) return false;
  if (startMinutes < endMinutes) {
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  }
  return currentMinutes >= startMinutes || currentMinutes < endMinutes;
}

export function getQuietHoursEnd(
  quietEnd: string,
  timezone: string,
  now: Date = new Date(),
): Date {
  const end = parseLocalTime(quietEnd);
  if (!end) {
    throw new Error('invalid quiet hours end');
  }

  const timeZone = resolveTimeZone(timezone);
  const localNow = getZonedDateParts(now, timeZone);
  const endToday = zonedDateToUtc(timeZone, localNow.year, localNow.month, localNow.day, end.hours, end.minutes);
  if (endToday.getTime() > now.getTime()) {
    return endToday;
  }

  const nextDay = shiftLocalDate(localNow, 1);
  return zonedDateToUtc(timeZone, nextDay.year, nextDay.month, nextDay.day, end.hours, end.minutes);
}

export async function getAgentQuietHoursEnd(
  env: Env,
  agentId: string,
  now: Date = new Date(),
): Promise<Date | null> {
  const rows = await env.DB
    .prepare(
      `SELECT
         COALESCE(json_extract(preferences, '$.quiet_hours_start'), json_extract(preferences, '$.quiet_hours.start')) AS quiet_start,
         COALESCE(json_extract(preferences, '$.quiet_hours_end'), json_extract(preferences, '$.quiet_hours.end')) AS quiet_end,
         COALESCE(json_extract(preferences, '$.quiet_hours.timezone'), json_extract(preferences, '$.timezone')) AS timezone,
         json_extract(preferences, '$.quiet_hours.enabled') AS enabled
       FROM bosses
       WHERE preferences IS NOT NULL
         AND (
           role = 'admin'
           OR agent_id = ?
           OR id IN (SELECT boss_id FROM boss_agent_access WHERE agent_id = ?)
         )`
    )
    .bind(agentId, agentId)
    .all<QuietHoursRow>();

  let latestEnd: Date | null = null;
  for (const row of rows.results ?? []) {
    // Honor an explicit `enabled: false`; a missing flag (legacy/flat format)
    // stays enabled so existing quiet-hours windows keep working.
    if (row.enabled === 0) continue;
    if (!isInQuietHours(row.quiet_start, row.quiet_end, row.timezone, now) || !row.quiet_end) {
      continue;
    }
    const quietEnd = getQuietHoursEnd(row.quiet_end, row.timezone ?? DEFAULT_TIME_ZONE, now);
    if (!latestEnd || quietEnd.getTime() > latestEnd.getTime()) {
      latestEnd = quietEnd;
    }
  }
  return latestEnd;
}

function parseLocalTime(value: string | null): LocalTime | null {
  if (!value) return null;
  const match = TIME_PATTERN.exec(value);
  if (!match) return null;
  return {
    hours: Number(match[1]),
    minutes: Number(match[2]),
  };
}

function resolveTimeZone(timezone: string | null): string {
  const candidate = timezone?.trim();
  if (!candidate) return DEFAULT_TIME_ZONE;
  try {
    getFormatter(candidate);
    return candidate;
  } catch {
    return DEFAULT_TIME_ZONE;
  }
}

function getFormatter(timeZone: string): Intl.DateTimeFormat {
  const cached = formatterCache.get(timeZone);
  if (cached) return cached;
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  });
  formatterCache.set(timeZone, formatter);
  return formatter;
}

function getZonedDateParts(date: Date, timeZone: string): ZonedDateParts {
  const parts = getFormatter(timeZone).formatToParts(date);
  const values: Record<string, string> = {};
  for (const part of parts) {
    if (part.type !== 'literal') {
      values[part.type] = part.value;
    }
  }
  return {
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
    hours: Number(values.hour),
    minutes: Number(values.minute),
    seconds: Number(values.second),
  };
}

function zonedDateToUtc(timeZone: string, year: number, month: number, day: number, hours: number, minutes: number): Date {
  const utcGuess = Date.UTC(year, month - 1, day, hours, minutes, 0, 0);
  const firstOffset = getTimeZoneOffsetMs(timeZone, new Date(utcGuess));
  const firstPass = new Date(utcGuess - firstOffset);
  const secondOffset = getTimeZoneOffsetMs(timeZone, firstPass);
  return secondOffset === firstOffset ? firstPass : new Date(utcGuess - secondOffset);
}

function getTimeZoneOffsetMs(timeZone: string, date: Date): number {
  const parts = getZonedDateParts(date, timeZone);
  const zonedAsUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hours, parts.minutes, parts.seconds, 0);
  return zonedAsUtc - date.getTime();
}

function shiftLocalDate(parts: ZonedDateParts, days: number): Pick<ZonedDateParts, 'year' | 'month' | 'day'> {
  const shifted = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + days, 12, 0, 0, 0));
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}
