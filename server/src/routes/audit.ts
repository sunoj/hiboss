// Audit log query endpoint.
// Exports auditRouter mounted at /api/audit.
// Depends on Hono, auth middleware, and D1 bindings.

import { Hono } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const params = c.req.query();
  const actorType = params.actor_type as string | undefined;
  const action = params.action as string | undefined;
  const limit = Math.min(parseInt(params.limit ?? '50', 10), 200);
  const offset = parseInt(params.offset ?? '0', 10);

  void agentId; // auth required, but audit is global read
  const clauses: string[] = [];
  const binds: (string | number)[] = [];

  if (actorType) {
    clauses.push('actor_type = ?');
    binds.push(actorType);
  }
  if (action) {
    clauses.push('action = ?');
    binds.push(action);
  }

  let sql = 'SELECT * FROM audit_log';
  if (clauses.length > 0) sql += ` WHERE ${clauses.join(' AND ')}`;
  const countSql = sql.replace('SELECT *', 'SELECT COUNT(*) as count');
  const countRow = await c.env.DB.prepare(countSql).bind(...binds).first<{ count: number }>();
  const total = countRow?.count ?? 0;

  sql += ' ORDER BY created_at DESC LIMIT ? OFFSET ?';
  binds.push(limit, offset);

  const rows = await c.env.DB.prepare(sql).bind(...binds).all();
  return c.json({ entries: rows.results ?? [], total });
});

export const auditRouter = routes;