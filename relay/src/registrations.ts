// Registration routes: create, rotate the APNs token, and delete (opt-out).
// The bundle is fixed server-side; deviceSecret is the only credential for /self. One row per
// APNs token. Each route checks body size and its per-source rate (no D1) before any D1 access.

import { Hono } from 'hono';
import { randomToken } from './crypto';
import { ceilingReached, globalRegistrationCheck, recordSuccess, sourceLimited } from './limits';
import { bearer, gone, invalid, tooMany, unavailable } from './responses';
import { deleteRegistration, findBySecret, insertRegistration, updateToken } from './store';
import type { AppEnv, TokenBody } from './types';
import { declaredSizeOk, parseJsonObject, parseTokenBody, readLimitedBody } from './validate';

export const registrations = new Hono<AppEnv>();

type Gate = 'ok' | 'invalid' | 'limited';

async function gate(limiter: RateLimit, request: Request, withBody: boolean): Promise<Gate> {
  if (withBody && !declaredSizeOk(request)) return 'invalid';
  return (await sourceLimited(limiter, request)) ? 'limited' : 'ok';
}

async function tokenBody(request: Request): Promise<TokenBody | null> {
  const json = parseJsonObject(await readLimitedBody(request));
  return json && parseTokenBody(json);
}

registrations.post('/', async (c) => {
  const gated = await gate(c.env.REGISTRATION_RATE_LIMITER, c.req.raw, true);
  if (gated !== 'ok') return gated === 'limited' ? tooMany(c) : invalid(c);
  const body = await tokenBody(c.req.raw);
  if (!body) return invalid(c);
  const now = Date.now();
  if (await ceilingReached(c.env.DB, globalRegistrationCheck, now)) return unavailable(c);
  const handle = randomToken();
  const deviceSecret = randomToken();
  await insertRegistration(c.env.DB, handle, deviceSecret, body, now);
  await recordSuccess(c.env.DB, globalRegistrationCheck, now);
  return c.json({ handle, deviceSecret }, 201);
});

registrations.put('/self', async (c) => {
  const gated = await gate(c.env.SELF_RATE_LIMITER, c.req.raw, true);
  if (gated !== 'ok') return gated === 'limited' ? tooMany(c) : invalid(c);
  const body = await tokenBody(c.req.raw);
  if (!body) return invalid(c);
  const now = Date.now();
  const row = await findBySecret(c.env.DB, bearer(c));
  if (!row) return gone(c);
  await updateToken(c.env.DB, row.handle_hash, body, now);
  return c.body(null, 204);
});

registrations.delete('/self', async (c) => {
  if ((await gate(c.env.SELF_RATE_LIMITER, c.req.raw, false)) === 'limited') return tooMany(c);
  const row = await findBySecret(c.env.DB, bearer(c));
  if (row) await deleteRegistration(c.env.DB, row.handle_hash);
  return c.body(null, 204);
});
