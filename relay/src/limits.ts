// Abuse limits: per-source request rates in Workers Rate Limiting bindings (no D1), and
// fixed-window D1 counters per device, keyed on SHA-256 of the APNs token.

export const HOUR_MS = 3_600_000;
export const DAY_MS = 86_400_000;

export const LIMITS = {
  devicePerHour: 60,
  devicePerDay: 500,
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

/**
 * Push rate-limit key: the `CF-Worker` zone (or `-`), `|`, and the client address key. Never the
 * header alone: a forged header only splits the forger's own address budget, and Worker
 * subrequests sharing an egress address still get one bucket per zone.
 */
export function sourceKey(request: Request): string {
  const worker = request.headers.get('CF-Worker')?.toLowerCase() || '-';
  return `${worker}|${clientKey(request)}`;
}

/**
 * Registration rate-limit key: the IPv6 /64 prefix or the full IPv4 address of
 * `CF-Connecting-IP` only. Registrations come from phones, so `CF-Worker` is ignored.
 */
export function clientKey(request: Request): string {
  const ip = request.headers.get('CF-Connecting-IP') ?? '';
  if (ip.includes('.')) return ip.slice(ip.lastIndexOf(':') + 1);
  if (!ip.includes(':')) return ip || 'unknown';
  return ipv6Prefix64(ip);
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

/** Applies a Rate Limiting binding to a key; true when the caller is over its rate. */
export async function sourceLimited(limiter: RateLimit, key: string): Promise<boolean> {
  const { success } = await limiter.limit({ key });
  return !success;
}
