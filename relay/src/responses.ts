// Fixed JSON error bodies shared by every relay route.
// One body per status keeps unknown and invalid capabilities indistinguishable.

import type { Context } from 'hono';
import type { AppEnv } from './types';

type Ctx = Context<AppEnv>;

export const invalid = (c: Ctx) => c.json({ error: 'invalid_request' }, 400);
export const gone = (c: Ctx) => c.json({ error: 'gone' }, 410);
export const tooMany = (c: Ctx) => c.json({ error: 'rate_limited' }, 429);
export const unavailable = (c: Ctx) => c.json({ error: 'unavailable' }, 503);
export const upstreamFailed = (c: Ctx) => c.json({ error: 'apns_failed' }, 502);

export function bearer(c: Ctx): string {
  const header = c.req.header('Authorization') ?? '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : '';
}
