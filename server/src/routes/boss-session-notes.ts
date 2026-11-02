// Boss note creation and history with exact session authorization.
// Exports bossNotesRouter; depends on shared boss access and note storage.
import { Hono, type Context } from 'hono';
import { HTTPException } from 'hono/http-exception';
import type { Env } from '../types';
import { bossAuth, getBossId, getBossRole } from '../middleware/auth';
import { getAccessibleAgentIds } from './boss-api-access';
import { NOTE_SELECT, type Note } from './session-notes';
import { noteImage, withImages } from './note-images';
import { createNote } from './note-create';
import { withReplies } from './note-replies';

const routes = new Hono<{ Bindings: Env }>();
routes.onError((error) => {
  if (error instanceof HTTPException) return error.getResponse();
  throw error;
});
routes.use('/sessions/:id/notes', bossAuth);
routes.use('/sessions/:id/notes/*', bossAuth);
async function sessionAgent(c: Context<{ Bindings: Env }>): Promise<string | null> {
  const agents = await getAccessibleAgentIds(c.env, getBossId(c), getBossRole(c));
  const session = await c.env.DB.prepare('SELECT agent_id FROM sessions WHERE id = ?')
    .bind(c.req.param('id')).first<{ agent_id: string }>();
  return session && agents.includes(session.agent_id) ? session.agent_id : null;
}
routes.get('/sessions/:id/notes', async (c) => {
  if (!await sessionAgent(c)) return c.text('not found', 404);
  const rows = await c.env.DB.prepare(`${NOTE_SELECT} WHERE n.session_id = ?
    ORDER BY n.created_at DESC, n.rowid DESC LIMIT 50`).bind(c.req.param('id')).all<Note>();
  const notes = await withReplies(c.env, rows.results);
  return c.json({ notes: await Promise.all(notes.map(note => withImages(c.env, note))) });
});
routes.post('/sessions/:id/notes', async (c) => {
  if (getBossRole(c) === 'viewer') return c.text('viewer cannot write notes', 403);
  const agent = await sessionAgent(c);
  if (!agent) return c.text('not found', 404);
  return createNote(c, agent);
});
routes.get('/sessions/:id/notes/:noteId/images/:index', async (c) => {
  if (!await sessionAgent(c)) return c.text('not found', 404);
  return noteImage(c);
});
export const bossNotesRouter = routes;
