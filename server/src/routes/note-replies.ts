// Validate note-linked sends and enrich note responses with batched reply history.
// Uses the existing message persistence batch and displayable message content.
import type { Context } from 'hono';
import type { Env } from '../types';
import type { SendInput } from './message-send-input';

interface NoteReply { message_id: string; body: string; agent_name: string; created_at: string }

export async function validateNoteReply(c: Context<{ Bindings: Env }>, input: SendInput):
Promise<Response | null> {
  const id = input.clientMetadata?.note_id;
  if (id === undefined) return null;
  if (typeof id !== 'string' || !id.trim()) return c.text('note_id must be a non-empty string', 400);
  if (input.toAgent) return c.text('note replies must be agent-to-boss messages', 400);
  if (input.options || input.mode === 'blocking') return c.text('note replies cannot be asks', 400);
  if (input.fileUrl || input.messageType !== 'text') return c.text('note replies must be text only', 400);
  if (!input.sessionId) return c.text('note replies require session_id', 400);
  const note = await c.env.DB.prepare(`SELECT id FROM session_notes
    WHERE id = ? AND session_id = ? AND agent_id = ?`)
    .bind(id, input.sessionId, input.agentId).first();
  return note ? null : c.text('note does not belong to this session and agent', 400);
}

export function noteReplyStatements(env: Env, metadata: string | null, messageId: string):
D1PreparedStatement[] {
  const id: unknown = metadata ? (JSON.parse(metadata) as Record<string, unknown>).note_id : undefined;
  if (typeof id !== 'string') return [];
  return [
    env.DB.prepare('INSERT INTO session_note_replies (note_id, message_id) VALUES (?, ?)')
      .bind(id, messageId),
    env.DB.prepare(`UPDATE session_notes SET status = 'read', read_at = datetime('now')
      WHERE id = ? AND status = 'pending'`).bind(id),
  ];
}

export async function withReplies<T extends { id: string }>(env: Env, notes: T[]):
Promise<(T & { replies: NoteReply[] })[]> {
  if (!notes.length) return [];
  const rows = await env.DB.prepare(`SELECT r.note_id, m.id AS message_id, m.body, m.metadata,
    a.name AS agent_name, r.created_at FROM session_note_replies r
    JOIN messages m ON m.id = r.message_id JOIN api_keys a ON a.id = m.agent_id
    WHERE r.note_id IN (SELECT value FROM json_each(?)) ORDER BY r.created_at, r.rowid`)
    .bind(JSON.stringify(notes.map(note => note.id)))
    .all<NoteReply & { note_id: string; metadata: string | null }>();
  const grouped = new Map<string, NoteReply[]>();
  for (const row of rows.results) {
    const metadata = row.metadata ? JSON.parse(row.metadata) as Record<string, unknown> : null;
    const content = metadata?.content;
    const reply = { message_id: row.message_id, body: typeof content === 'string' && content.trim()
      ? content : row.body, agent_name: row.agent_name, created_at: row.created_at };
    const replies = grouped.get(row.note_id) ?? [];
    replies.push(reply);
    grouped.set(row.note_id, replies);
  }
  return notes.map(note => ({ ...note, replies: grouped.get(note.id) ?? [] }));
}
