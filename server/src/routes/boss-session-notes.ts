// Boss note creation and history with exact session authorization.
// Exports bossNotesRouter; depends on shared boss access and note storage.
import { Hono } from 'hono';
import type { Env } from '../types';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api-access';
import { NOTE_SELECT, type Note } from './session-notes';

const routes = new Hono<{ Bindings: Env; Variables: { noteAgent: string } }>();
routes.use('/sessions/:id/notes', bossAuth);
routes.use('/sessions/:id/notes', async (c, next) => {
  if (c.req.method === 'POST' && getBossRole(c) === 'viewer') return c.text('viewer cannot write notes', 403);
  const agents = await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c));
  const session = await c.env.DB.prepare('SELECT agent_id FROM sessions WHERE id = ?')
    .bind(c.req.param('id')).first<{ agent_id: string }>();
  if (!session || !agents.includes(session.agent_id)) return c.text('not found', 404);
  c.set('noteAgent', session.agent_id);
  await next();
});
routes.get('/sessions/:id/notes', async (c) => {
  const rows = await c.env.DB.prepare(`${NOTE_SELECT} WHERE n.session_id = ?
    ORDER BY n.created_at DESC, n.rowid DESC LIMIT 50`).bind(c.req.param('id')).all<Note>();
  return c.json({ notes: rows.results });
});
routes.post('/sessions/:id/notes', async (c) => {
  const payload = await c.req.json<{ body?: unknown }>().catch(() => null);
  const body = typeof payload?.body === 'string' ? payload.body.trim() : '';
  if (!body || [...body].length > 4000) return c.text('body must contain 1..4000 characters', 400);
  const db = c.env.DB;
  const boss = getBossId(c);
  const session = c.req.param('id');
  const key = c.req.header('Idempotency-Key');
  const id = crypto.randomUUID();
  if (key !== undefined) {
    // The batch claims a retry key and inserts only its winning note, atomically.
    await db.batch([
      db.prepare(`INSERT INTO session_notes (id, session_id, agent_id, boss_id, body)
        SELECT ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM session_note_keys
        WHERE boss_id = ? AND session_id = ? AND key = ?)`)
        .bind(id, session, c.get('noteAgent'), boss, body, boss, session, key),
      db.prepare(`INSERT INTO session_note_keys (boss_id, session_id, key, note_id)
        VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING`).bind(boss, session, key, id),
    ]);
    const note = await db.prepare(`${NOTE_SELECT} JOIN session_note_keys k ON k.note_id = n.id
      WHERE k.boss_id = ? AND k.session_id = ? AND k.key = ?`).bind(boss, session, key).first<Note>();
    return c.json(note, note?.id === id ? 201 : 200);
  }
  await db.prepare(`INSERT INTO session_notes (id, session_id, agent_id, boss_id, body)
    VALUES (?, ?, ?, ?, ?)`)
    .bind(id, session, c.get('noteAgent'), boss, body).run();
  const note = await db.prepare(`${NOTE_SELECT} WHERE n.id = ?`).bind(id).first<Note>();
  return c.json(note, 201);
});
export const bossNotesRouter = routes;
