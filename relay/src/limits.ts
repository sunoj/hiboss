// Abuse limits: per-source request rates in the Workers Rate Limiting binding (no D1),
// and fixed-window D1 counters per handle and for the relay-wide push and registration ceilings.

import type { Env } from './types';

export const HOUR_MS = 3_600_000;
export const DAY_MS = 86_400_000;
export const DEFAULT_GLOBAL_DAILY_LIMIT = 200_000;
export const GLOBAL_PUSH_SCOPE = 'global';
export const GLOBAL_REGISTRATION_SCOPE = 'global:reg';

export const LIMITS = {
  handlePerHour: 60,
  handlePerDay: 500,
  registrationsPerHour: 5_000,
} as const;

export interface LimitCheck {
  scope: string;
  periodMs: number;
  max: number;
}

export function counterKey(scope: string, periodMs: number, now: number): string {
  return `${scope}|${periodMs}|${Math.floor(now / periodMs)}`;
}

function incrementStatement(db: D1Database, check: LimitCheck, now: number): D1PreparedStatement {
  const window = Math.floor(now / check.periodMs);
  return db
    .prepare(
      'INSERT INTO rate_counters (key, count, expires_at) VALUES (?, 1, ?) ' +
        'ON CONFLICT(key) DO UPDATE SET count = count + 1 RETURNING count',
    )
    .bind(counterKey(check.scope, check.periodMs, now), (window + 1) * check.periodMs);
}

/** Increments every counter in one batch; true when any of them is now above its max. */
export async function overLimit(db: D1Database, checks: LimitCheck[], now: number): Promise<boolean> {
  const results = await db.batch<{ count: number }>(checks.map((check) => incrementStatement(db, check, now)));
  return results.some((result, i) => (result.results[0]?.count ?? 0) > checks[i].max);
}

/** Reads a ceiling without writing; true when its window already holds `max` successes. */
export async function ceilingReached(db: D1Database, check: LimitCheck, now: number): Promise<boolean> {
  const row = await db
    .prepare('SELECT count FROM rate_counters WHERE key = ?')
    .bind(counterKey(check.scope, check.periodMs, now))
    .first<{ count: number }>();
  return (row?.count ?? 0) >= check.max;
}

/** Records one success against a ceiling checked with `ceilingReached`. */
export async function recordSuccess(db: D1Database, check: LimitCheck, now: number): Promise<void> {
  await incrementStatement(db, check, now).run();
}

export function globalPushCheck(env: Env): LimitCheck {
  const parsed = Number(env.GLOBAL_DAILY_PUSH_LIMIT);
  const max = Number.isInteger(parsed) && parsed > 0 ? parsed : DEFAULT_GLOBAL_DAILY_LIMIT;
  return { scope: GLOBAL_PUSH_SCOPE, periodMs: DAY_MS, max };
}

export const globalRegistrationCheck: LimitCheck = {
  scope: GLOBAL_REGISTRATION_SCOPE,
  periodMs: HOUR_MS,
  max: LIMITS.registrationsPerHour,
};

/**
 * Rate-limit key for the caller: the `CF-Worker` zone for Worker subrequests (which share
 * Cloudflare egress addresses), else the IPv6 /64 prefix or the full IPv4 address.
 */
export function sourceKey(request: Request): string {
  const worker = request.headers.get('CF-Worker');
  if (worker) return `worker:${worker.toLowerCase()}`;
  const ip = request.headers.get('CF-Connecting-IP') ?? '';
  if (ip.includes('.')) return `ip:${ip.slice(ip.lastIndexOf(':') + 1)}`;
  if (!ip.includes(':')) return `ip:${ip || 'unknown'}`;
  return `ip6:${ipv6Prefix64(ip)}`;
}

/** First four hextets of an IPv6 address, expanded and normalized, e.g. `2001:db8:0:1::/64`. */
export function ipv6Prefix64(address: string): string {
  const [head, tail] = address.toLowerCase().split('::', 2);
  const headGroups = head ? head.split(':') : [];
  const tailGroups = tail === undefined ? [] : tail ? tail.split(':') : [];
  const missing = Math.max(0, 8 - headGroups.length - tailGroups.length);
  const groups = [...headGroups, ...Array<string>(missing).fill('0'), ...tailGroups];
  const prefix = groups
    .slice(0, 4)
    .map((group) => (/^[0-9a-f]{1,4}$/.test(group) ? parseInt(group, 16).toString(16) : '?'));
  return `${prefix.join(':')}::/64`;
}

/** Applies a per-source Rate Limiting binding; true when the caller is over its rate. */
export async function sourceLimited(limiter: RateLimit, request: Request): Promise<boolean> {
  const { success } = await limiter.limit({ key: sourceKey(request) });
  return !success;
}
