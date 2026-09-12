// Boss-controlled agent enrolment requests and approval.
// Exports bossJoinRouter; inherits bossApiRouter auth and uses audited creation/D1.
import { Hono } from 'hono';
import type { Env } from '../types';
import { getBossId, getBossRole } from '../middleware/auth';
import { createAgent } from '../agent-keys';
import { logAudit } from '../audit';
interface JoinRequestRow { id: string; name: string; status: string; created_at: string; updated_at: string }
const routes = new Hono<{ Bindings: Env }>();
routes.get('/join-requests', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const status = c.req.query('status');
  const sql = status
    ? 'SELECT id, name, status, created_at, updated_at FROM join_requests WHERE status = ? ORDER BY created_at DESC'
    : 'SELECT id, name, status, created_at, updated_at FROM join_requests ORDER BY created_at DESC';
  const query = c.env.DB.prepare(sql);
  const rows = status
    ? await query.bind(status).all<JoinRequestRow>()
    : await query.all<JoinRequestRow>();
  return c.json({ requests: rows.results ?? [] });
});

routes.post('/join-requests/:id/approve', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const bossId = getBossId(c);
  const requestId = c.req.param('id');
  const request = await c.env.DB.prepare('SELECT * FROM join_requests WHERE id = ?').bind(requestId).first<JoinRequestRow>();
  if (!request) return c.text('not found', 404);
  if (request.status !== 'pending') return c.text('request already processed', 400);
  const inserted = await createAgent(c.env.DB, request.name, { type: 'boss', id: bossId });
  if (!inserted) return c.text('agent name already exists', 409);
  await c.env.DB
    .prepare("UPDATE join_requests SET status = 'approved', api_key_id = ?, api_key = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(inserted.id, inserted.key, request.id)
    .run();
  await c.env.DB
    .prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, inserted.id)
    .run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'join.approve', 'join_request', request.id));
  return c.json({ id: request.id, name: request.name, status: 'approved', agent_id: inserted.id, key: inserted.key });
});

routes.post('/join-requests/:id/reject', async (c) => {
  if (getBossRole(c) !== 'admin') return c.text('admin access required', 403);
  const bossId = getBossId(c);
  const requestId = c.req.param('id');
  const request = await c.env.DB.prepare('SELECT * FROM join_requests WHERE id = ?').bind(requestId).first<JoinRequestRow>();
  if (!request) return c.text('not found', 404);
  if (request.status !== 'pending') return c.text('request already processed', 400);
  await c.env.DB
    .prepare("UPDATE join_requests SET status = 'rejected', updated_at = datetime('now') WHERE id = ?")
    .bind(request.id)
    .run();
  c.executionCtx.waitUntil(logAudit(c.env, 'boss', bossId, 'join.reject', 'join_request', request.id));
  return c.json({ id: request.id, name: request.name, status: 'rejected' });
});

export const bossJoinRouter = routes;
