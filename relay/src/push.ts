// POST /v1/push: the handle is the capability; the relay forwards opaque ciphertext to APNs.
// Order: size → body → handle MAC → per-handle rate (no D1) → lookup → per-device limits → APNs.
// A request that reaches D1 carries a genuine handle. There is no relay-wide push ceiling. Device
// counters are keyed on SHA-256 of the APNs token, so re-registering a token does not reset them.

import { Hono } from 'hono';
import { sendApns } from './apns';
import { sha256Hex } from './crypto';
import { handleValid } from './handles';
import { DAY_MS, HOUR_MS, LIMITS, overLimit, rateLimited } from './limits';
import { gone, invalid, tooMany, unavailable, upstreamFailed } from './responses';
import { deleteRegistration, findByHandle, touch } from './store';
import type { AppEnv } from './types';
import { declaredSizeOk, parseJsonObject, parsePushBody, readLimitedBody } from './validate';

export const push = new Hono<AppEnv>();

push.post('/', async (c) => {
  if (!declaredSizeOk(c.req.raw)) return invalid(c);
  const json = parseJsonObject(await readLimitedBody(c.req.raw));
  const body = json && parsePushBody(json);
  if (!body) return invalid(c);
  const handleKey = c.env.HANDLE_KEY;
  if (!handleKey) return unavailable(c);
  if (!(await handleValid(handleKey, body.handle))) return gone(c);
  if (await rateLimited(c.env.HANDLE_RATE_LIMITER, await sha256Hex(body.handle))) return tooMany(c);
  const db = c.env.DB;
  const now = Date.now();
  const row = await findByHandle(db, body.handle);
  if (!row) return gone(c);
  const scope = `token:${await sha256Hex(row.apns_token)}`;
  const deviceChecks = [
    { scope, periodMs: HOUR_MS, max: LIMITS.devicePerHour },
    { scope, periodMs: DAY_MS, max: LIMITS.devicePerDay },
  ];
  if (await overLimit(db, deviceChecks, now)) return tooMany(c);
  const outcome = await sendApns(c.env, {
    apnsToken: row.apns_token,
    environment: row.environment,
    kind: body.kind,
    ciphertext: body.ciphertext,
    collapseId: body.collapseId,
    priority: body.priority,
    interruption: body.interruption,
    sound: body.sound,
  });
  if (outcome === 'gone') {
    await deleteRegistration(db, row.handle_hash);
    return gone(c);
  }
  if (outcome === 'unconfigured') return unavailable(c);
  if (outcome === 'failed') return upstreamFailed(c);
  await touch(db, row.handle_hash, now);
  return c.body(null, 202);
});
