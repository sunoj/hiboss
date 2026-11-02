// Session note storage and agent-only read routes.
// Exports agentNotesRouter and shared note selection; depends on Hono and D1.
import { Hono, type MiddlewareHandler } from 'hono';
import type { Env } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';

export interface Note {
  id: string;
  session_id: string;
  agent_id: string;
  boss_name: string;
  body: string;
  status: 'pending' | 'read';
  created_at: string;
  read_at: string | null;
}
export const NOTE_SELECT = `SELECT n.id, n.session_id, n.agent_id,
  COALESCE(b.name, 'Deleted boss') AS boss_name,
  n.body, n.status, n.created_at, n.read_at FROM session_notes n LEFT JOIN bosses b ON b.id = n.boss_id`;

const routes = new Hono<{ Bindings: Env }>();
routes.use('/:id/notes', apiAuth);
routes.use('/:id/notes/*', apiAuth);
const ownSession: MiddlewareHandler<{ Bindings: Env }> = async (c, next) => {
  const session = await c.env.DB.prepare('SELECT id FROM sessions WHERE id = ? AND agent_id = ?')
    .bind(c.req.param('id'), getAgentId(c)).first();
  if (!session) return c.text('not found', 404);
  await next();
};
routes.use('/:id/notes', ownSession);
routes.use('/:id/notes/*', ownSession);
routes.get('/:id/notes', async (c) => {
  const status = c.req.query('status') ?? 'pending';
  if (status !== 'pending' && status !== 'all') return c.text('invalid status', 400);
  const rows = await c.env.DB.prepare(`${NOTE_SELECT} WHERE n.session_id = ? AND n.agent_id = ?
    ${status === 'pending' ? "AND n.status = 'pending'" : ''} ORDER BY n.created_at, n.rowid`)
    .bind(c.req.param('id'), getAgentId(c)).all<Note>();
  return c.json({ notes: rows.results });
});
routes.post('/:id/notes/read', async (c) => {
  const payload = await c.req.json<{ ids?: unknown }>().catch(() => null);
  const ids = payload?.ids;
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > 50
    || !ids.every((id): id is string => typeof id === 'string')) {
    return c.text('ids must contain 1..50 strings', 400);
  }
  const result = await c.env.DB.prepare(`UPDATE session_notes SET status = 'read', read_at = datetime('now')
    WHERE session_id = ? AND agent_id = ? AND status = 'pending'
    AND id IN (${ids.map(() => '?').join(',')})`)
    .bind(c.req.param('id'), getAgentId(c), ...ids).run();
  return c.json({ read: result.meta.changes });
});
export const agentNotesRouter = routes;
