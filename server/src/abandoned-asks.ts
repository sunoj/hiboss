// Expires asks nobody can still be waiting on: their session ended, or they are a day old
// with no deadline. Exports the session-end helpers, expireStaleAsks and STALE_ASK_SQL.
// Depends on the shared expiry SQL — an abandoned ask is expired, never answered by default.
import type { Env, MessageRow } from './types';
import { OPEN_MESSAGE_STATUS } from './message-status';
import { announceExpiredAsk, EXPIRE_ASK_SET_SQL, expireWithoutDefault } from './routes/message-options';

const BATCH_SIZE = 50;
/** Ceiling on stale-sweep batches per cron run; the next run continues from what is left. */
const MAX_STALE_BATCHES = 20;

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

/**
 * One statement that expires every open ask of an ended session, so a caller can put it in
 * the same batch that ends the session. Pass its rows to announceSessionAsks after commit.
 */
export function sessionAsksExpiry(db: D1Database, agentId: string, sessionId: string): D1PreparedStatement {
  return db.prepare(`UPDATE messages SET ${EXPIRE_ASK_SET_SQL}
    WHERE agent_id = ? AND session_id = ? AND ${OPEN_ASK_SQL} RETURNING *`).bind(agentId, sessionId);
}

/** Best-effort chat edits for the asks a committed sessionAsksExpiry returned. */
export async function announceSessionAsks(env: Env, rows: MessageRow[]): Promise<void> {
  for (const row of rows) await announceExpiredAsk(env, row.agent_id, row);
}

/** Ends a session's asks the way every completing path must: all expire, none by default. */
export async function expireSessionAsks(env: Env, agentId: string, sessionId: string): Promise<number> {
  const rows = (await sessionAsksExpiry(env.DB, agentId, sessionId).all<MessageRow>()).results ?? [];
  await announceSessionAsks(env, rows);
  return rows.length;
}

/** Cron sweep: expires deadline-less asks older than a day, up to MAX_STALE_BATCHES batches. */
export async function expireStaleAsks(env: Env): Promise<number> {
  let expired = 0;
  for (let batch = 0; batch < MAX_STALE_BATCHES; batch += 1) {
    const rows = (await env.DB
      .prepare(`SELECT * FROM messages WHERE ${OPEN_ASK_SQL} AND ${STALE_ASK_SQL} LIMIT ?`)
      .bind(BATCH_SIZE)
      .all<MessageRow>()).results ?? [];
    const claimed = await expireAll(env, rows);
    expired += claimed;
    // A short batch is the last one; a batch that claimed nothing would only repeat itself.
    if (rows.length < BATCH_SIZE || claimed === 0) break;
  }
  return expired;
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
