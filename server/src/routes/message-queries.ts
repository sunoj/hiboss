/**
 * Database query functions for message-related data.
 * Handles fetching messages, replies, channel configurations, and rate limiting.
 */

import type { Channel, Env, MessageRow } from '../types';
import { mapMessageRow } from './message-helpers';

export async function selectChannelConfig(env: Env, agentId: string, requested?: Channel) {
  if (requested) {
    const exact = await env.DB
      .prepare("SELECT channel, config FROM channel_configs WHERE agent_id = ? AND enabled = 1 AND channel = ? LIMIT 1")
      .bind(agentId, requested)
      .first<{ channel: Channel; config: string }>();
    if (exact) {
      return { channel: exact.channel, config: JSON.parse(exact.config) as Record<string, unknown> };
    }
  }
  const fallback = await env.DB
    .prepare("SELECT channel, config FROM channel_configs WHERE agent_id = ? AND enabled = 1 ORDER BY created_at DESC LIMIT 1")
    .bind(agentId)
    .first<{ channel: Channel; config: string }>();
  if (!fallback) {
    throw new Error('no channel configured');
  }
  return { channel: fallback.channel, config: JSON.parse(fallback.config) as Record<string, unknown> };
}

export async function fetchAllChannelConfigs(env: Env, agentId: string) {
  const rows = await env.DB
    .prepare('SELECT channel, config FROM channel_configs WHERE agent_id = ? AND enabled = 1')
    .bind(agentId)
    .all<{ channel: Channel; config: string }>();
  return (rows.results ?? []).map((r) => ({
    channel: r.channel,
    config: JSON.parse(r.config) as Record<string, unknown>,
  }));
}

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

function isDecisionReply(parent: MessageRow, reply: { agent_id: string; direction: string }): boolean {
  if (parent.direction === 'agent_to_agent') return reply.direction === 'agent_to_agent' && reply.agent_id !== parent.agent_id;
  if (parent.direction === 'agent_to_boss') return reply.direction === 'boss_to_agent';
  return true;
}

export async function fetchAgentName(env: Env, agentId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ name: string }>();
  return row?.name ?? null;
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
