// Atomic message/event persistence for session streams.
// Exports insertMessageWithEvent and the session event SQL used by message writers.
// Depends on D1 and the shared MessageRow/Env types.

import type { Env, MessageRow } from './types';

const EVENT_INSERT_SQL = `
  INSERT INTO session_events (
    session_id, sequence, kind, direction, actor_agent_id, target_agent_id,
    message_id, source, payload, raw
  )
  SELECT
    ?,
    COALESCE((SELECT MAX(sequence) FROM session_events WHERE session_id = ?), 0) + 1,
    'message',
    messages.direction,
    messages.agent_id,
    messages.target_agent_id,
    messages.id,
    json_object('record_type', 'message', 'source_version', 'v1'),
    json_object(
      'body', messages.body,
      'priority', messages.priority,
      'mode', messages.mode,
      'channel', messages.channel,
      'type', messages.type,
      'status', messages.status,
      'reply_to', messages.reply_to,
      'metadata', CASE WHEN json_valid(messages.metadata) THEN json(messages.metadata) ELSE messages.metadata END
    ),
    json_object(
      'id', messages.id,
      'agent_id', messages.agent_id,
      'direction', messages.direction,
      'mode', messages.mode,
      'channel', messages.channel,
      'body', messages.body,
      'status', messages.status,
      'reply_to', messages.reply_to,
      'priority', messages.priority,
      'type', messages.type,
      'target_agent_id', messages.target_agent_id,
      'target_session_id', messages.target_session_id,
      'session_id', messages.session_id,
      'idempotency_key', messages.idempotency_key,
      'metadata', CASE WHEN json_valid(messages.metadata) THEN json(messages.metadata) ELSE messages.metadata END,
      'created_at', messages.created_at,
      'updated_at', messages.updated_at,
      'expires_at', messages.expires_at
    )
  FROM messages
  WHERE messages.id = ?`;

export function createMessageId(): string {
  return crypto.randomUUID().replaceAll('-', '');
}

export async function insertMessageWithEvent(
  env: Env,
  insertSql: string,
  insertBinds: readonly unknown[],
  sessionId: string | null,
): Promise<MessageRow | null> {
  const messageStatement = env.DB.prepare(insertSql).bind(...insertBinds);
  if (!sessionId) return await messageStatement.first<MessageRow>();

  const eventStatement = env.DB.prepare(EVENT_INSERT_SQL).bind(sessionId, sessionId, insertBinds[0]);
  const results = await env.DB.batch([messageStatement, eventStatement]);
  return results[0]?.results[0] as MessageRow | undefined ?? null;
}
