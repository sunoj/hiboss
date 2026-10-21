// POST /v1/push: the handle is the capability; the relay forwards opaque ciphertext to APNs.
// Order: size → source rate (no D1) → body → handle → per-handle limits → APNs.
// There is no relay-wide push ceiling: one registration per APNs token bounds pushes per device.

import { Hono } from 'hono';
import { sendApns } from './apns';
import { DAY_MS, HOUR_MS, LIMITS, overLimit, sourceLimited } from './limits';
import { gone, invalid, tooMany, unavailable, upstreamFailed } from './responses';
import { deleteRegistration, findByHandle, touch } from './store';
import type { AppEnv } from './types';
import { declaredSizeOk, parseJsonObject, parsePushBody, readLimitedBody } from './validate';

export const push = new Hono<AppEnv>();

push.post('/', async (c) => {
  if (!declaredSizeOk(c.req.raw)) return invalid(c);
  if (await sourceLimited(c.env.PUSH_RATE_LIMITER, c.req.raw)) return tooMany(c);
  const json = parseJsonObject(await readLimitedBody(c.req.raw));
  const body = json && parsePushBody(json);
  if (!body) return invalid(c);
  const db = c.env.DB;
  const now = Date.now();
  const row = await findByHandle(db, body.handle);
  if (!row) return gone(c);
  const scope = `handle:${row.handle_hash}`;
  const handleChecks = [
    { scope, periodMs: HOUR_MS, max: LIMITS.handlePerHour },
    { scope, periodMs: DAY_MS, max: LIMITS.handlePerDay },
  ];
  if (await overLimit(db, handleChecks, now)) return tooMany(c);
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
