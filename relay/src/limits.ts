// Abuse limits: request rates in Workers Rate Limiting bindings (no D1), per address for
// registrations and per handle for pushes, and fixed-window D1 counters per device, keyed on
// SHA-256 of the APNs token.

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

/**
 * Increments every counter in one statement, and only while all of them are under their max:
 * the guard is evaluated before any write, so an over-limit call writes nothing. True when the
 * statement returned no row, i.e. some counter was already at its max.
 */
export async function overLimit(db: D1Database, checks: LimitCheck[], now: number): Promise<boolean> {
  const keys = checks.map((check) => counterKey(check.scope, check.periodMs, now));
  const values = checks.map(() => '(?, ?)').join(', ');
  const full = checks.map(() => '(key = ? AND count >= ?)').join(' OR ');
  const statement = db
    .prepare(
      `INSERT INTO rate_counters (key, count, expires_at) SELECT column1, 1, column2 FROM (VALUES ${values}) ` +
        `WHERE NOT EXISTS (SELECT 1 FROM rate_counters WHERE ${full}) ` +
        'ON CONFLICT(key) DO UPDATE SET count = count + 1 RETURNING count',
    )
    .bind(
      ...checks.flatMap((check, i) => [keys[i], (Math.floor(now / check.periodMs) + 1) * check.periodMs]),
      ...checks.flatMap((check, i) => [keys[i], check.max]),
    );
  const { results } = await statement.all<{ count: number }>();
  return results.length === 0;
}

/** Registration rate-limit key: the IPv6 /64 prefix or the full IPv4 address of `CF-Connecting-IP`. */
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
export async function rateLimited(limiter: RateLimit, key: string): Promise<boolean> {
  const { success } = await limiter.limit({ key });
  return !success;
}
