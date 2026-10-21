// Registration routes: create, rotate the APNs token, and delete (opt-out).
// The bundle is fixed server-side; deviceSecret is the only credential for /self. One row per
// APNs token, stored only after APNs accepts a background push to it; handles carry a HANDLE_KEY
// MAC. Each route checks body size and its per-address rate (no D1) before any D1 access.

import { type Context, Hono } from 'hono';
import { type TokenCheck, verifyToken } from './apns';
import { randomToken } from './crypto';
import { mintHandle } from './handles';
import { clientKey, rateLimited } from './limits';
import { bearer, gone, invalid, invalidToken, tooMany, unavailable } from './responses';
import { deleteRegistration, findBySecret, insertRegistration, updateToken } from './store';
import type { AppEnv, TokenBody } from './types';
import { declaredSizeOk, parseJsonObject, parseTokenBody, readLimitedBody } from './validate';

export const registrations = new Hono<AppEnv>();

type Gate = 'ok' | 'invalid' | 'limited';

async function gate(limiter: RateLimit, request: Request, withBody: boolean): Promise<Gate> {
  if (withBody && !declaredSizeOk(request)) return 'invalid';
  return (await rateLimited(limiter, clientKey(request))) ? 'limited' : 'ok';
}

/** The response for a token APNs did not accept; null when it did. Nothing is written either way. */
function rejected(c: Context<AppEnv>, check: TokenCheck): Response | null {
  if (check === 'valid') return null;
  return check === 'invalid' ? invalidToken(c) : unavailable(c);
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
  const handleKey = c.env.HANDLE_KEY;
  if (!handleKey) return unavailable(c);
  const failure = rejected(c, await verifyToken(c.env, body));
  if (failure) return failure;
  const handle = await mintHandle(handleKey);
  const deviceSecret = randomToken();
  await insertRegistration(c.env.DB, handle, deviceSecret, body, Date.now());
  return c.json({ handle, deviceSecret }, 201);
});

registrations.put('/self', async (c) => {
  const gated = await gate(c.env.SELF_RATE_LIMITER, c.req.raw, true);
  if (gated !== 'ok') return gated === 'limited' ? tooMany(c) : invalid(c);
  const body = await tokenBody(c.req.raw);
  if (!body) return invalid(c);
  const row = await findBySecret(c.env.DB, bearer(c));
  if (!row) return gone(c);
  const failure = rejected(c, await verifyToken(c.env, body));
  if (failure) return failure;
  await updateToken(c.env.DB, row.handle_hash, body, Date.now());
  return c.body(null, 204);
});

registrations.delete('/self', async (c) => {
  if ((await gate(c.env.SELF_RATE_LIMITER, c.req.raw, false)) === 'limited') return tooMany(c);
  const row = await findBySecret(c.env.DB, bearer(c));
  if (row) await deleteRegistration(c.env.DB, row.handle_hash);
  return c.body(null, 204);
});
