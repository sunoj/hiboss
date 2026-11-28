/**
 * Database query functions for message-related data.
 * Handles fetching messages, replies, and rate limiting.
 */

import type { Env, MessageRow } from '../types';
import { mapMessageRow } from './message-helpers';
import { isDecisionReply } from '../decision-answerability';

export async function fetchMessageRow(env: Env, agentId: string, messageId: string) {
  const exact = await env.DB
    .prepare(
      'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id = ? AND (messages.agent_id = ? OR messages.target_agent_id = ?)'
    )
    .bind(messageId, agentId, agentId)
    .first<MessageRow>();
  if (exact) {
    return exact;
  }
  return env.DB
    .prepare(
      'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id LIKE ? AND (messages.agent_id = ? OR messages.target_agent_id = ?) LIMIT 1'
    )
    .bind(`${messageId}%`, agentId, agentId)
    .first<MessageRow>();
}

export async function fetchReplies(env: Env, parentId: string, agentId?: string) {
  const replyFilter = agentId
    ? 'WHERE reply_to = ? AND (messages.agent_id = ? OR messages.target_agent_id = ?)'
    : 'WHERE reply_to = ?';
  const binds = agentId ? [parentId, agentId, agentId] : [parentId];
  const result = await env.DB
    .prepare(
      `SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id ${replyFilter} ORDER BY messages.created_at ASC`
    )
    .bind(...binds)
    .all<MessageRow>();
  return (result.results ?? []).map(mapMessageRow);
}

/**
 * `decisionsOnly` keeps only replies that can answer the message: a boss_to_agent row for a
 * boss ask, a peer's row for an agent-to-agent ask. The asker's own follow-ups and forward
 * copies (both authored by the asker) never answer it.
 */
export async function fetchMessageWithReplies(env: Env, agentId: string, messageId: string, decisionsOnly = false) {
  const row = await fetchMessageRow(env, agentId, messageId);
  if (!row) {
    return null;
  }
  const replyList = await fetchReplies(env, row.id, agentId);
  return { ...mapMessageRow(row), replies: decisionsOnly ? replyList.filter(reply => isDecisionReply(row, reply)) : replyList };
}

export async function checkRateLimit(env: Env, agentId: string, limit: number): Promise<boolean> {
  const recent = await env.DB
    .prepare("SELECT COUNT(*) AS count FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND created_at > datetime('now', '-1 minute')")
    .bind(agentId)
    .first<{ count: number }>();
  return !!(recent && recent.count >= limit);
}

export async function findByIdempotencyKey(env: Env, agentId: string, key: string): Promise<MessageRow | null> {
  return env.DB
    .prepare('SELECT * FROM messages WHERE agent_id = ? AND idempotency_key = ?')
    .bind(agentId, key)
    .first<MessageRow>();
}
