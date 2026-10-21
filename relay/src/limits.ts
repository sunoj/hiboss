// Fixed-window abuse counters stored in D1 (per handle, per source IP, global).
// A hit increments first and then compares, so rejected attempts also count.

import { sha256Hex } from './crypto';
import type { Env } from './types';

export const HOUR_MS = 3_600_000;
export const DAY_MS = 86_400_000;
export const DEFAULT_GLOBAL_DAILY_LIMIT = 50_000;

export const LIMITS = {
  handlePerHour: 60,
  handlePerDay: 500,
  ipPushPerHour: 600,
  ipRegistrationPerHour: 30,
} as const;

export interface LimitCheck {
  scope: string;
  periodMs: number;
  max: number;
}

export function counterKey(scope: string, periodMs: number, now: number): string {
  return `${scope}|${periodMs}|${Math.floor(now / periodMs)}`;
}

/** Increments every counter in one batch; true when any of them is now above its max. */
export async function overLimit(db: D1Database, checks: LimitCheck[], now: number): Promise<boolean> {
  const statements = checks.map((check) => {
    const window = Math.floor(now / check.periodMs);
    return db
      .prepare(
        'INSERT INTO rate_counters (key, count, expires_at) VALUES (?, 1, ?) ' +
          'ON CONFLICT(key) DO UPDATE SET count = count + 1 RETURNING count',
      )
      .bind(counterKey(check.scope, check.periodMs, now), (window + 1) * check.periodMs);
  });
  const results = await db.batch<{ count: number }>(statements);
  return results.some((result, i) => (result.results[0]?.count ?? 0) > checks[i].max);
}

export async function ipScope(request: Request, bucket: 'push' | 'reg'): Promise<string> {
  const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
  return `ip:${bucket}:${await sha256Hex(ip)}`;
}

export function globalDailyLimit(env: Env): number {
  const parsed = Number(env.GLOBAL_DAILY_PUSH_LIMIT);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : DEFAULT_GLOBAL_DAILY_LIMIT;
}
