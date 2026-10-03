// Boss-controlled device enrolment requests and approval.
// Exports bossJoinRouter; inherits bossApiRouter auth and uses the atomic device approval.
import { Hono } from 'hono';
import type { Env } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';
import { logAudit } from '../audit';
import { approveJoin, rejectJoin } from '../devices/approve';
import { parseStoredProfiles, type JoinRequestRow } from '../devices/types';

const LIST_COLUMNS = 'id, status, device_label, device_host, device_id, profiles, created_at, updated_at';
const routes = new Hono<{ Bindings: Env }>();

routes.get('/join-requests', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const status = c.req.query('status');
  const query = c.env.DB.prepare(status
    ? `SELECT ${LIST_COLUMNS} FROM join_requests WHERE status = ? ORDER BY created_at DESC`
    : `SELECT ${LIST_COLUMNS} FROM join_requests ORDER BY created_at DESC`);
  const rows = await (status ? query.bind(status) : query).all<Omit<JoinRequestRow, 'delivery'>>();
  const requests = (rows.results ?? []).map(row => ({ ...row, profiles: parseStoredProfiles(row.profiles) }));
  return c.json({ requests });
});

routes.post('/join-requests/:id/approve', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const bossId = getBossId(c);
  const requestId = c.req.param('id');
  const outcome = await approveJoin(c.env.DB, requestId, { type: 'boss', id: bossId }, { approverBossId: bossId });
  if (!outcome.ok) return c.text(outcome.error, outcome.status);
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'join.approve', 'join_request', requestId));
  return c.json({ id: requestId, status: 'approved', device_id: outcome.deviceId, agents: outcome.agents });
});

routes.post('/join-requests/:id/reject', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const bossId = getBossId(c);
  const requestId = c.req.param('id');
  const outcome = await rejectJoin(c.env.DB, requestId);
  if (!outcome.ok) return c.text(outcome.error, outcome.status);
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'join.reject', 'join_request', requestId));
  return c.json({ id: requestId, status: 'rejected' });
});

export const bossJoinRouter = routes;
