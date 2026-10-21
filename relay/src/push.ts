// POST /v1/push: the handle is the capability; the relay forwards opaque ciphertext to APNs.
// Order: body → source-IP limit → handle → per-handle limits → global ceiling → APNs.

import { Hono } from 'hono';
import { sendApns } from './apns';
import { DAY_MS, HOUR_MS, LIMITS, globalDailyLimit, ipScope, overLimit } from './limits';
import { gone, invalid, tooMany, unavailable, upstreamFailed } from './responses';
import { deleteRegistration, findByHandle, touch } from './store';
import type { AppEnv } from './types';
import { parseJsonObject, parsePushBody } from './validate';

export const push = new Hono<AppEnv>();

push.post('/', async (c) => {
  const json = parseJsonObject(await c.req.text());
  const body = json && parsePushBody(json);
  if (!body) return invalid(c);
  const db = c.env.DB;
  const now = Date.now();
  const ip = await ipScope(c.req.raw, 'push');
  if (await overLimit(db, [{ scope: ip, periodMs: HOUR_MS, max: LIMITS.ipPushPerHour }], now)) {
    return tooMany(c);
  }
  const row = await findByHandle(db, body.handle);
  if (!row) return gone(c);
  const scope = `handle:${row.handle_hash}`;
  const handleChecks = [
    { scope, periodMs: HOUR_MS, max: LIMITS.handlePerHour },
    { scope, periodMs: DAY_MS, max: LIMITS.handlePerDay },
  ];
  if (await overLimit(db, handleChecks, now)) return tooMany(c);
  if (await overLimit(db, [{ scope: 'global', periodMs: DAY_MS, max: globalDailyLimit(c.env) }], now)) {
    return unavailable(c);
  }
  const outcome = await sendApns(c.env, {
    apnsToken: row.apns_token,
    environment: row.environment,
    kind: body.kind,
    ciphertext: body.ciphertext,
    collapseId: body.collapseId,
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
