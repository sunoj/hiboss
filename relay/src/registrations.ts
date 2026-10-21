// Registration routes: create, rotate the APNs token, and delete (opt-out).
// The bundle is fixed server-side; deviceSecret is the only credential for /self.

import { Hono } from 'hono';
import { randomToken } from './crypto';
import { HOUR_MS, LIMITS, ipScope, overLimit } from './limits';
import { bearer, gone, invalid, tooMany } from './responses';
import { deleteRegistration, findBySecret, insertRegistration, updateToken } from './store';
import type { AppEnv } from './types';
import { parseJsonObject, parseTokenBody } from './validate';

export const registrations = new Hono<AppEnv>();

async function registrationLimited(request: Request, db: D1Database, now: number): Promise<boolean> {
  const scope = await ipScope(request, 'reg');
  return overLimit(db, [{ scope, periodMs: HOUR_MS, max: LIMITS.ipRegistrationPerHour }], now);
}

registrations.post('/', async (c) => {
  const json = parseJsonObject(await c.req.text());
  const body = json && parseTokenBody(json);
  if (!body) return invalid(c);
  const now = Date.now();
  if (await registrationLimited(c.req.raw, c.env.DB, now)) return tooMany(c);
  const handle = randomToken();
  const deviceSecret = randomToken();
  await insertRegistration(c.env.DB, handle, deviceSecret, body, now);
  return c.json({ handle, deviceSecret }, 201);
});

registrations.put('/self', async (c) => {
  const json = parseJsonObject(await c.req.text());
  const body = json && parseTokenBody(json);
  if (!body) return invalid(c);
  const now = Date.now();
  if (await registrationLimited(c.req.raw, c.env.DB, now)) return tooMany(c);
  const row = await findBySecret(c.env.DB, bearer(c));
  if (!row) return gone(c);
  await updateToken(c.env.DB, row.handle_hash, body, now);
  return c.body(null, 204);
});

registrations.delete('/self', async (c) => {
  const now = Date.now();
  if (await registrationLimited(c.req.raw, c.env.DB, now)) return tooMany(c);
  const row = await findBySecret(c.env.DB, bearer(c));
  if (row) await deleteRegistration(c.env.DB, row.handle_hash);
  return c.body(null, 204);
});
