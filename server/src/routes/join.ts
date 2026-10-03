// Join route for device enrolment: one request carries every runtime profile.
// Exports POST /api/join (invite, device proof or bootstrap secret) and GET /api/join/status.
// Depends on Hono, the devices module, bootstrap-secret policy and join notifications.

import { Hono } from 'hono';
import type { Env } from '../types';
import { logAudit } from '../audit';
import { hasValidBootstrapSecret } from '../middleware/bootstrap-secret';
import { createJoinRequest, pollJoinRequest, resolveDeviceProof, takenNames } from '../devices/enroll';
import { consumeInvite, inviteIsLive } from '../devices/invites';
import { parseJoinPayload } from '../devices/types';
import { notifyJoinConnected, notifyJoinRequest } from './join-notify';

const INVITE_REQUIRED = 'an invite is required; run `hiboss device invite` on an enrolled machine';
const INVITE_DEAD = 'invite is invalid, already used or expired';
const router = new Hono<{ Bindings: Env }>({});

router.post('/', async (c) => {
  // An empty server takes the bootstrap secret in place of an invite; the request still waits for a boss.
  const agents = await c.env.DB.prepare('SELECT COUNT(*) AS cnt FROM api_keys').first<{ cnt: number }>();
  const empty = Number(agents?.cnt ?? 0) === 0;
  if (empty && !c.env.BOOTSTRAP_SECRET) return c.json({ error: 'set BOOTSTRAP_SECRET on the server to enrol the first machine' }, 403);
  if (empty && !hasValidBootstrapSecret(c)) return c.json({ error: 'bootstrap secret required' }, 401);
  const payload = parseJoinPayload(await c.req.json<unknown>().catch(() => null));
  if (typeof payload === 'string') return c.json({ error: payload }, 400);
  const proof = c.req.header('X-Device-Proof');
  const deviceId = proof ? await resolveDeviceProof(c.env.DB, proof) : null;
  if (proof && !deviceId) return c.json({ error: 'invalid device proof' }, 401);
  // A live invite is checked before names are revealed, and spent only after the name check.
  const needsInvite = !empty && !deviceId;
  if (needsInvite && !payload.invite) return c.json({ error: INVITE_REQUIRED }, 403);
  if (needsInvite && payload.invite && !await inviteIsLive(c.env.DB, payload.invite)) return c.json({ error: INVITE_DEAD }, 403);
  const conflicts = await takenNames(c.env.DB, payload.profiles.map(p => p.name));
  if (conflicts.length) return c.json({ error: 'agent name already exists', conflicts }, 409);
  const invite = needsInvite && payload.invite ? await consumeInvite(c.env.DB, payload.invite) : null;
  if (needsInvite && !invite) return c.json({ error: INVITE_DEAD }, 403);
  const created = await createJoinRequest(c.env.DB, payload, { deviceId, invite });
  const names = payload.profiles.map(p => p.name).join(', ');
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'join_request.create', 'join_request', created.requestId, names));
  c.executionCtx.waitUntil(notifyJoinRequest(c.env, { requestId: created.requestId, deviceLabel: created.deviceLabel,
    profiles: payload.profiles, inviterLabel: invite?.inviterLabel ?? null, verificationCode: created.verificationCode,
    existingDevice: !!deviceId }));
  return c.json({ request_id: created.requestId, poll_token: created.pollToken, status: 'pending',
    verification_code: created.verificationCode }, 201);
});

router.get('/status', async (c) => {
  const token = c.req.query('token');
  if (!token) return c.json({ error: 'missing token' }, 400);
  const result = await pollJoinRequest(c.env.DB, token);
  if (!result) return c.json({ error: 'not found' }, 404);
  const body = {
    request_id: result.requestId,
    status: result.status,
    device_label: result.deviceLabel,
    verification_code: result.verificationCode,
    profiles: result.profiles,
    ...(result.delivered ? { delivered: true } : {}),
    ...result.delivery,
  };
  if (result.delivery) {
    const delivery = result.delivery;
    c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'join_request.key_delivered', 'join_request', result.requestId, result.deviceLabel));
    c.executionCtx.waitUntil(notifyJoinConnected(c.env, result.deviceLabel, delivery.profiles).catch(() => {}));
  }
  return c.json(body);
});

export const joinRouter = router;
