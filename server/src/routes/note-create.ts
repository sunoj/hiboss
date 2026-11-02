// Persist note uploads before atomically inserting note, image metadata and retry key.
// Exports createNote; uses shared selection, image validation and best-effort R2 cleanup.
import type { Context } from 'hono';
import type { Env } from '../types';
import { getBossId } from '../middleware/auth';
import { NOTE_SELECT, type Note } from './session-notes';
import { notePayload, withImages, type UploadImage } from './note-images';

async function retry(env: Env, boss: string, session: string, key: string): Promise<Note | null> {
  return env.DB.prepare(`${NOTE_SELECT} JOIN session_note_keys k ON k.note_id = n.id
    WHERE k.boss_id = ? AND k.session_id = ? AND k.key = ?`).bind(boss, session, key).first<Note>();
}

function statements(env: Env, id: string, session: string, agent: string, boss: string,
  body: string, key: string | undefined, images: UploadImage[]): D1PreparedStatement[] {
  const insert = key === undefined
    ? env.DB.prepare(`INSERT INTO session_notes (id, session_id, agent_id, boss_id, body)
      VALUES (?, ?, ?, ?, ?)`).bind(id, session, agent, boss, body)
    : env.DB.prepare(`INSERT INTO session_notes (id, session_id, agent_id, boss_id, body)
      SELECT ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM session_note_keys
      WHERE boss_id = ? AND session_id = ? AND key = ?)`)
      .bind(id, session, agent, boss, body, boss, session, key);
  const rows = [insert];
  if (key !== undefined) rows.push(env.DB.prepare(`INSERT INTO session_note_keys
    (boss_id, session_id, key, note_id) VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING`)
    .bind(boss, session, key, id));
  images.forEach((image, index) => rows.push(env.DB.prepare(`INSERT INTO session_note_images
    (note_id, idx, content_type, bytes, r2_key) SELECT ?, ?, ?, ?, ?
    WHERE EXISTS (SELECT 1 FROM session_notes WHERE id = ?)`)
    .bind(id, index, image.content_type, image.data.byteLength, `notes/${id}/${index}`, id)));
  return rows;
}

export async function createNote(c: Context<{ Bindings: Env }>, agent: string): Promise<Response> {
  const boss = getBossId(c);
  const session = c.req.param('id') ?? '';
  const key = c.req.header('Idempotency-Key');
  if (key !== undefined) {
    const original = await retry(c.env, boss, session, key);
    if (original) return c.json(await withImages(c.env, original), 200);
  }
  const { body, images } = await notePayload(c);
  const id = crypto.randomUUID();
  const keys = images.map((_, index) => `notes/${id}/${index}`);
  let retained = false;
  try {
    for (const [index, image] of images.entries()) {
      await c.env.ATTACHMENTS.put(keys[index], image.data,
        { httpMetadata: { contentType: image.content_type } });
    }
    await c.env.DB.batch(statements(c.env, id, session, agent, boss, body, key, images));
    const note = key === undefined
      ? await c.env.DB.prepare(`${NOTE_SELECT} WHERE n.id = ?`).bind(id).first<Note>()
      : await retry(c.env, boss, session, key);
    retained = note?.id === id;
    if (!note) throw new Error('created note not found');
    return c.json(await withImages(c.env, note), retained ? 201 : 200);
  } finally {
    if (!retained) await Promise.allSettled(keys.map(key => c.env.ATTACHMENTS.delete(key)));
  }
}
