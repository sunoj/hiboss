-- Append-only per-session event log, including an ordered message backfill.
CREATE TABLE IF NOT EXISTS session_events (
  id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
  session_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  kind TEXT NOT NULL,
  direction TEXT,
  actor_agent_id TEXT,
  target_agent_id TEXT,
  message_id TEXT REFERENCES messages(id),
  source TEXT,
  payload TEXT,
  raw TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
  UNIQUE (session_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_session_events_cursor ON session_events(session_id, sequence);

WITH ordered_messages AS (
  SELECT
    messages.*,
    COALESCE(messages.session_id, messages.target_session_id) AS event_session_id,
    ROW_NUMBER() OVER (
      PARTITION BY COALESCE(messages.session_id, messages.target_session_id)
      ORDER BY messages.created_at, messages.id
    ) AS event_sequence
  FROM messages
  WHERE COALESCE(messages.session_id, messages.target_session_id) IS NOT NULL
)
INSERT INTO session_events (
  session_id, sequence, kind, direction, actor_agent_id, target_agent_id,
  message_id, source, payload, raw
)
SELECT
  event_session_id,
  event_sequence,
  'message',
  direction,
  agent_id,
  target_agent_id,
  id,
  json_object('record_type', 'message', 'source_version', 'v1'),
  json_object(
    'body', body,
    'priority', priority,
    'mode', mode,
    'channel', channel,
    'type', type,
    'status', status,
    'reply_to', reply_to,
    'metadata', CASE WHEN json_valid(metadata) THEN json(metadata) ELSE metadata END
  ),
  json_object(
    'id', id,
    'agent_id', agent_id,
    'direction', direction,
    'mode', mode,
    'channel', channel,
    'body', body,
    'status', status,
    'reply_to', reply_to,
    'priority', priority,
    'type', type,
    'target_agent_id', target_agent_id,
    'target_session_id', target_session_id,
    'session_id', session_id,
    'idempotency_key', idempotency_key,
    'metadata', CASE WHEN json_valid(metadata) THEN json(metadata) ELSE metadata END,
    'created_at', created_at,
    'updated_at', updated_at,
    'expires_at', expires_at
  )
FROM ordered_messages;
