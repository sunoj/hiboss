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

  // Agents may only read their own audit trail; the global log is boss-scoped
  // (GET /api/boss/audit). Prevents cross-agent disclosure of the whole log.
  const clauses: string[] = ["actor_type = 'agent'", 'actor_id = ?'];
  const binds: (string | number)[] = [agentId];

  if (actorType && actorType !== 'agent') {
    // An agent's own entries are always actor_type='agent'; any other filter is empty.
    return c.json({ entries: [], total: 0 });
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