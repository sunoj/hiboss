// Complete, scoped pending-input discovery for the iOS Home surface.
// Exports fetchRequiredInputPage; depends on D1 rows and message mapping.
// Keeps a stable created_at/id keyset across pages.

import type { Env, MessageResponse, MessageRow } from '../types';
import { mapMessageRow } from './message-helpers';

const PAGE_SIZE = 100;

export interface RequiredInputPage {
  messages: MessageResponse[];
  next_cursor: string | null;
}

export interface RequiredInputCursor { createdAt: string; id: string }

export function decodeRequiredInputCursor(value: string | undefined): RequiredInputCursor | null {
  if (!value) return null;
  try {
    const parsed = JSON.parse(atob(value)) as Record<string, unknown>;
    if (typeof parsed.createdAt === 'string' && typeof parsed.id === 'string'
        && parsed.createdAt.length > 0 && parsed.id.length > 0) {
      return { createdAt: parsed.createdAt, id: parsed.id };
    }
  } catch { /* Invalid cursors are rejected by the route. */ }
  throw new Error('invalid pending-input cursor');
}

export async function fetchRequiredInputPage(
  env: Env, agentIds: string[], cursor: RequiredInputCursor | null, now: string,
): Promise<RequiredInputPage> {
  if (agentIds.length === 0) return { messages: [], next_cursor: null };
  const placeholders = agentIds.map(() => '?').join(', ');
  const keyset = cursor ? 'AND (messages.created_at < ? OR (messages.created_at = ? AND messages.id < ?))' : '';
  const binds: (string | number)[] = [...agentIds, now];
  if (cursor) binds.push(cursor.createdAt, cursor.createdAt, cursor.id);
  const rows = await env.DB.prepare(
    `SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label,
            sessions.branch AS session_branch, sessions.status AS session_status
     FROM messages
     LEFT JOIN api_keys ON api_keys.id = messages.agent_id
     LEFT JOIN sessions ON sessions.id = messages.session_id
     WHERE messages.agent_id IN (${placeholders})
       AND messages.direction = 'agent_to_boss'
       AND messages.status IN ('sent', 'delivered', 'read')
       AND (messages.expires_at IS NULL OR messages.expires_at > ?)
       AND (CASE WHEN json_valid(messages.metadata)
            THEN json_extract(messages.metadata, '$.options_expired') IS NOT 1
            ELSE 1 END)
       AND (CASE WHEN json_valid(messages.metadata)
            THEN json_array_length(messages.metadata, '$.options') > 0
            ELSE 0 END
            OR messages.mode = 'blocking')
       ${keyset}
     ORDER BY messages.created_at DESC, messages.id DESC LIMIT ?`,
  ).bind(...binds, PAGE_SIZE + 1).all<MessageRow>();
  if (!rows.success || !rows.results) throw new Error('incomplete pending-input query');
  const result = rows.results;
  const page = result.slice(0, PAGE_SIZE);
  const last = page.at(-1);
  return {
    messages: page.map(mapMessageRow),
    next_cursor: result.length > PAGE_SIZE && last
      ? btoa(JSON.stringify({ createdAt: last.created_at, id: last.id })) : null,
  };
}

export async function fetchAllRequiredInputs(env: Env, agentIds: string[]): Promise<MessageResponse[]> {
  const messages: MessageResponse[] = [];
  let cursor: RequiredInputCursor | null = null;
  const now = new Date().toISOString();
  do {
    const page = await fetchRequiredInputPage(env, agentIds, cursor, now);
    messages.push(...page.messages);
    cursor = decodeRequiredInputCursor(page.next_cursor ?? undefined);
  } while (cursor);
  return messages;
}
