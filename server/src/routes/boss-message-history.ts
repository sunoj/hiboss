// Timestamp validation, access filters, and incremental boss message reads.
// Exports history query helpers; depends on D1 and the shared message mapper.
import type { Env, MessageResponse, MessageRow } from '../types';
import { mapMessageRow } from './message-helpers';

export interface MessageQuery {
  limit: number;
  offset: number;
  clauses: string[];
  binds: (string | number)[];
}

interface MessagePage {
  messages: MessageResponse[];
  total: number;
  cursor?: string;
  has_more?: boolean;
}

export function validMessageCursor(cursor: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(cursor)) return false;
  const date = new Date(cursor.replace(' ', 'T') + 'Z');
  return Number.isFinite(date.getTime()) && date.toISOString().replace('T', ' ').slice(0, 19) === cursor;
}

export function scopeMessageAgents(
  agentIds: string[], filter: string | undefined,
): Pick<MessageQuery, 'clauses' | 'binds'> | null {
  const match = filter ? agentIds.find(id => id === filter || id.startsWith(filter)) : undefined;
  if (filter && !match) return null;
  return {
    clauses: [match ? 'agent_id = ?' : `agent_id IN (${agentIds.map(() => '?').join(', ')})`],
    binds: match ? [match] : [...agentIds],
  };
}

export function emptyMessagePage(cursor: string | undefined): MessagePage {
  return cursor === undefined ? { messages: [], total: 0 }
    : { messages: [], total: 0, cursor, has_more: false };
}

export async function fetchMessageDelta(env: Env, query: MessageQuery, cursor: string): Promise<MessagePage> {
  const where = [...query.clauses, 'updated_at >= ?'].join(' AND ');
  const binds = [...query.binds, cursor];
  const limit = Math.max(1, Math.floor(query.limit));
  const count = await env.DB.prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`)
    .bind(...binds).first<{ total: number }>();
  const rows = await env.DB
    .prepare(`SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label,
      sessions.branch AS session_branch, sessions.status AS session_status
      FROM (SELECT * FROM messages INDEXED BY idx_messages_agent_updated
        WHERE ${where} ORDER BY updated_at ASC, id ASC LIMIT ? OFFSET ?) messages
      LEFT JOIN api_keys ON api_keys.id = messages.agent_id
      LEFT JOIN sessions ON sessions.id = messages.session_id
      ORDER BY messages.updated_at ASC, messages.id ASC`)
    .bind(...binds, limit, query.offset).all<MessageRow>();
  const messages = (rows.results ?? []).map(mapMessageRow);
  return {
    messages,
    total: count?.total ?? 0,
    cursor: messages.at(-1)?.updated_at ?? cursor,
    has_more: messages.length === limit,
  };
}
