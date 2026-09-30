// Expires asks nobody can still be waiting on: their session ended, or they are a day old
// with no deadline. Exports expireSessionAsks, expireStaleAsks and STALE_ASK_SQL.
// Depends on expireWithoutDefault — an abandoned ask is expired, never answered by default.
import type { Env, MessageRow } from './types';
import { OPEN_MESSAGE_STATUS } from './message-status';
import { expireWithoutDefault } from './routes/message-options';

const BATCH_SIZE = 50;

/** An open agent question: offered options, or a blocking text ask. */
const OPEN_ASK_SQL = `direction = 'agent_to_boss' AND ${OPEN_MESSAGE_STATUS}
  AND (CASE WHEN json_valid(metadata) THEN json_array_length(metadata, '$.options') > 0 ELSE 0 END
       OR mode = 'blocking')`;

/**
 * An ask without its own deadline that has waited more than a day. `hiboss ask` stops
 * waiting after its local timeout (30 min by default), so no agent is behind it any more.
 * julianday() accepts both SQLite and ISO timestamps.
 */
export const STALE_ASK_SQL = "expires_at IS NULL AND julianday(created_at) < julianday('now') - 1";

/** Expires every open ask of a session that has ended; returns how many were open. */
export async function expireSessionAsks(env: Env, agentId: string, sessionId: string): Promise<number> {
  const rows = await env.DB
    .prepare(`SELECT * FROM messages WHERE agent_id = ? AND session_id = ? AND ${OPEN_ASK_SQL} LIMIT ?`)
    .bind(agentId, sessionId, BATCH_SIZE)
    .all<MessageRow>();
  return expireAll(env, rows.results ?? []);
}

/** Cron sweep: expires deadline-less asks older than a day, one batch per run. */
export async function expireStaleAsks(env: Env): Promise<number> {
  const rows = await env.DB
    .prepare(`SELECT * FROM messages WHERE ${OPEN_ASK_SQL} AND ${STALE_ASK_SQL} LIMIT ?`)
    .bind(BATCH_SIZE)
    .all<MessageRow>();
  return expireAll(env, rows.results ?? []);
}

async function expireAll(env: Env, rows: MessageRow[]): Promise<number> {
  let expired = 0;
  for (const row of rows) {
    try {
      if (await expireWithoutDefault(env, row.agent_id, row)) expired += 1;
    } catch {
      console.error(`Failed to expire abandoned ask ${row.id}`);
    }
  }
  return expired;
}
