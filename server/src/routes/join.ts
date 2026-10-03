// Join route for device enrolment: one request carries every runtime profile.
// Exports POST /api/join and GET /api/join/status without auth.
// Depends on Hono, the devices module, bootstrap-secret policy and join notifications.

import { Hono } from 'hono';
import type { Env } from '../types';
import { logAudit } from '../audit';
import { hasValidBootstrapSecret } from '../middleware/bootstrap-secret';
import { createJoinRequest, pollJoinRequest, resolveDeviceProof } from '../devices/enroll';
import { parseJoinPayload } from '../devices/types';
import { notifyJoinConnected, notifyJoinRequest } from './join-notify';

const router = new Hono<{ Bindings: Env }>({});

router.post('/', async (c) => {
  const agents = await c.env.DB.prepare('SELECT COUNT(*) AS cnt FROM api_keys').first<{ cnt: number }>();
  const bootstrap = Number(agents?.cnt ?? 0) === 0;
  if (bootstrap && !hasValidBootstrapSecret(c)) return c.json({ error: 'bootstrap secret required' }, 401);
  const payload = parseJoinPayload(await c.req.json<unknown>().catch(() => null));
  if (typeof payload === 'string') return c.json({ error: payload }, 400);
  const proof = c.req.header('X-Device-Proof');
  const deviceId = proof ? await resolveDeviceProof(c.env.DB, proof) : null;
  if (proof && !deviceId) return c.json({ error: 'invalid device proof' }, 401);
  const outcome = await createJoinRequest(c.env.DB, payload, deviceId, bootstrap);
  if (outcome.kind === 'conflict') {
    return c.json({ error: 'agent name already exists', conflicts: outcome.names }, 409);
  }
  const names = payload.profiles.map(p => p.name).join(', ');
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'join_request.create', 'join_request', outcome.requestId, names));
  if (outcome.status === 'pending') {
    c.executionCtx.waitUntil(notifyJoinRequest(c.env, outcome.requestId, payload.device.label, payload.profiles));
    return c.json({ request_id: outcome.requestId, poll_token: outcome.pollToken, status: 'pending' }, 201);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'join_request.approve', 'join_request', outcome.requestId, 'bootstrap'));
  return c.json({ request_id: outcome.requestId, poll_token: outcome.pollToken, status: 'approved', ...outcome.delivery }, 201);
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
