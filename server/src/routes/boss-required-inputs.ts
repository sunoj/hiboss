// Complete, scoped pending-input discovery for the iOS Home surface.
// Exports the paged full scan and the incremental stream refresh; depends on D1 rows and message mapping.
// Keeps a stable created_at/id keyset across pages.

import type { Env, MessageResponse, MessageRow } from '../types';
import { DECISION_MESSAGE_SQL, OPEN_DECISION_SQL } from '../decision-answerability';
import { mapMessageRow } from './message-helpers';

const PAGE_SIZE = 100;

const REQUIRED_INPUT_SELECT = `SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label,
            sessions.branch AS session_branch, sessions.status AS session_status
     FROM messages
     LEFT JOIN api_keys ON api_keys.id = messages.agent_id
     LEFT JOIN sessions ON sessions.id = messages.session_id`;

/** Pending-input predicate; binds one `now` for the deadline. Time alone can make it false. */
const PENDING_SQL = `(${DECISION_MESSAGE_SQL})
       AND (${OPEN_DECISION_SQL})
       AND NOT (messages.expires_at IS NULL AND julianday(messages.created_at) < julianday('now') - 1)`;

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
  // Pending rows have a future deadline or none and are under a day old; each branch seeks an
  // index (agent_id, expires_at) / (agent_id, created_at). The date-prefix bound is two days back,
  // so it holds for both stored timestamp formats and for clock skew between Worker and D1.
  const recent = new Date(Date.parse(now) - 2 * 86_400_000).toISOString().slice(0, 10);
  const binds: (string | number)[] = [...agentIds, now, ...agentIds, recent, now];
  if (cursor) binds.push(cursor.createdAt, cursor.createdAt, cursor.id);
  const rows = await env.DB.prepare(
    `${REQUIRED_INPUT_SELECT}
     WHERE messages.rowid IN (
         SELECT rowid FROM messages WHERE agent_id IN (${placeholders}) AND expires_at > ?
         UNION ALL
         SELECT rowid FROM messages WHERE agent_id IN (${placeholders}) AND expires_at IS NULL AND created_at >= ?)
       AND ${PENDING_SQL}
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

/**
 * The pending inputs among rows updated at or after `since` (UTC `YYYY-MM-DD HH:MM:SS`) and the
 * tracked ids. Every way into the pending set updates the row, so after a full scan this returns
 * the complete current set while visiting only changed and tracked rows; a tracked id that is
 * absent has resolved, including by time alone (deadline passed, or the one-day abandonment).
 */
export async function fetchRequiredInputChanges(
  env: Env, agentIds: string[], trackedIds: string[], since: string,
): Promise<MessageResponse[]> {
  if (agentIds.length === 0) return [];
  const placeholders = agentIds.map(() => '?').join(', ');
  const rows = await env.DB.prepare(
    `${REQUIRED_INPUT_SELECT}
     WHERE messages.rowid IN (
         SELECT rowid FROM messages WHERE agent_id IN (${placeholders}) AND updated_at >= ?
         UNION ALL SELECT rowid FROM messages WHERE id IN (SELECT value FROM json_each(?)))
       AND ${PENDING_SQL}
     ORDER BY messages.created_at DESC, messages.id DESC`,
  ).bind(...agentIds, since, JSON.stringify(trackedIds), new Date().toISOString()).all<MessageRow>();
  if (!rows.success || !rows.results) throw new Error('incomplete pending-input query');
  return rows.results.map(mapMessageRow);
}
