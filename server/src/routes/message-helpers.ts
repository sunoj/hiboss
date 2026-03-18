// Helper functions for message route handlers: delivery, formatting, DB queries.
// Exports utility functions used by the messages router.
// Depends on types, channel adapters, and D1 bindings.

import type {
  Channel,
  Direction,
  Env,
  MessageResponse,
  MessageRow,
  Metadata,
  Priority,
  Status,
} from '../types';
import { createForumTopic, editMessageReplyMarkup } from '../channels/telegram';
import { editDiscordMessage } from '../channels/discord';
import { requireTelegramConfig as _requireTelegramConfig, requireDiscordConfig as _requireDiscordConfig, formatAgentMessage as _formatAgentMessage } from './delivery';
export { deliverReply, deliverToChannelWithOptions, deliverWithRetry, formatAgentMessage, requireDiscordConfig, requireTelegramConfig } from './delivery';
export type { DeliveryResult } from './delivery';

const channelOptions: Channel[] = ['discord', 'telegram', 'email', 'api'];
export const priorityOptions: Priority[] = ['critical', 'high', 'normal', 'low'];
const LIKE_ESCAPE_PATTERN = /[%_\\]/g;

export function mapMessageRow(row: MessageRow): MessageResponse {
  return {
    ...row,
    metadata: safeParse(row.metadata),
  };
}

function safeParse(value: string | null): Metadata {
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as Metadata;
  } catch {
    return null;
  }
}

export function normalizeMetadata(value: unknown): Metadata {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

export function validateOption<T extends string>(value: unknown, options: readonly T[], fallback?: T): T | null {
  if (typeof value === 'string' && options.includes(value as T)) {
    return value as T;
  }
  if (fallback) {
    return fallback;
  }
  return null;
}

export function validateChannel(value: unknown): Channel | undefined {
  if (typeof value === 'string' && channelOptions.includes(value as Channel)) {
    return value as Channel;
  }
  return undefined;
}

export function buildFilters(agentId: string, direction: Direction | null, status: Status | null, priority?: Priority[], type?: string, session?: string, unread?: boolean, from?: string, targetSessionId?: string, search?: string) {
  const clauses: string[] = [];
  const binds: (string | number)[] = [];
  // Unread: boss messages for this agent, agent-to-agent targeting this agent, or session-targeted messages
  if (unread) {
    if (direction === 'agent_to_agent') {
      // Narrowed unread: only agent-to-agent messages targeting this agent/session
      if (targetSessionId) {
        clauses.push("((target_agent_id = ? AND direction = 'agent_to_agent' AND target_session_id IS NULL) OR (target_session_id = ? AND direction = 'agent_to_agent'))");
        binds.push(agentId, targetSessionId);
      } else {
        clauses.push("(target_agent_id = ? AND direction = 'agent_to_agent')");
        binds.push(agentId);
      }
    } else if (targetSessionId) {
      clauses.push("((agent_id = ? AND direction = 'boss_to_agent') OR (target_agent_id = ? AND direction = 'agent_to_agent' AND target_session_id IS NULL) OR (target_session_id = ? AND direction = 'agent_to_agent'))");
      binds.push(agentId, agentId, targetSessionId);
    } else {
      clauses.push("((agent_id = ? AND direction = 'boss_to_agent') OR (target_agent_id = ? AND direction = 'agent_to_agent'))");
      binds.push(agentId, agentId);
    }
  } else {
    const visibilityClauses = ['agent_id = ?', 'target_agent_id = ?'];
    binds.push(agentId, agentId);
    if (targetSessionId) {
      visibilityClauses.push('(target_session_id = ? AND target_agent_id = ?)');
      binds.push(targetSessionId, agentId);
    }
    clauses.push(`(${visibilityClauses.join(' OR ')})`);
    if (direction) {
      clauses.push('direction = ?');
      binds.push(direction);
    }
  }
  if (status) {
    clauses.push('status = ?');
    binds.push(status);
  }
  if (priority && priority.length > 0) {
    const placeholders = priority.map(() => '?').join(', ');
    clauses.push(`priority IN (${placeholders})`);
    binds.push(...priority);
  }
  if (type) {
    clauses.push('type = ?');
    binds.push(type);
  }
  if (from) {
    clauses.push('agent_id IN (SELECT id FROM api_keys WHERE name = ? OR id LIKE ?)');
    binds.push(from, `${from.replace(LIKE_ESCAPE_PATTERN, '\\$&')}%`);
  }
  if (session && !unread) {
    // Show: messages from this session, boss replies to this session's messages,
    // and boss-initiated messages (reply_to IS NULL) visible to all sessions.
    clauses.push("(session_id = ? OR reply_to IN (SELECT id FROM messages WHERE session_id = ?) OR (direction = 'boss_to_agent' AND reply_to IS NULL))");
    binds.push(session, session);
  }
  if (search) {
    clauses.push('body LIKE ?');
    binds.push(`%${search}%`);
  }
  return { where: clauses.join(' AND '), binds };
}

export function parsePriorityFilter(value: string | undefined): Priority[] | undefined {
  if (!value) return undefined;
  const valid: Priority[] = [];
  for (const p of value.split(',')) {
    const trimmed = p.trim() as Priority;
    if (priorityOptions.includes(trimmed)) {
      valid.push(trimmed);
    }
  }
  return valid.length > 0 ? valid : undefined;
}

export function clampNumber(value: string | null | undefined, fallback: number, maximum: number): number {
  const parsed = Number(value ?? fallback);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(parsed, maximum);
}

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

export async function fetchMessageWithReplies(env: Env, agentId: string, messageId: string) {
  const row = await fetchMessageRow(env, agentId, messageId);
  if (!row) {
    return null;
  }
  const replyList = await fetchReplies(env, row.id, agentId);
  return { ...mapMessageRow(row), replies: replyList };
}


export async function fetchAgentName(env: Env, agentId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ name: string }>();
  return row?.name ?? null;
}

export function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}


export function parseOptions(value: unknown): string[] | undefined {
  if (Array.isArray(value) && value.every((v) => typeof v === 'string')) {
    return value.length > 0 ? (value as string[]) : undefined;
  }
  if (typeof value === 'string' && value.trim()) {
    return value.split(',').map((s) => s.trim()).filter(Boolean);
  }
  return undefined;
}

export function buildInlineKeyboard(messageId: string, options: string[]): { text: string; callback_data: string }[][] {
  return options.map((opt) => [{ text: opt, callback_data: `${messageId.slice(0, 12)}:${opt}` }]);
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

export async function expireMessageOptions(env: Env, agentId: string, message: MessageRow): Promise<void> {
  // 1. Update DB: set status to expired, mark options_expired in metadata
  const meta = message.metadata ? JSON.parse(message.metadata) as Record<string, unknown> : {};
  meta['options_expired'] = true;
  delete meta['actions'];
  await env.DB
    .prepare("UPDATE messages SET status = 'expired', metadata = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(JSON.stringify(meta), message.id)
    .run();
  // 2. Clean up channel inline keyboards
  const agentName = await fetchAgentName(env, agentId) ?? 'agent';
  if (message.channel === 'telegram') {
    const tgMsgId = extractTelegramMessageId(message.metadata);
    if (tgMsgId) {
      const cc = await selectChannelConfig(env, agentId, 'telegram');
      const tgConfig = _requireTelegramConfig(cc.config);
      const expiredText = _formatAgentMessage(agentName, message.body) + '\n\n⏰ Options expired';
      await editMessageReplyMarkup(tgConfig.bot_token, tgConfig.chat_id, tgMsgId, expiredText);
    }
  } else if (message.channel === 'discord') {
    const dcMsgId = meta['discord_message_id'] as string | undefined;
    if (dcMsgId) {
      const cc = await selectChannelConfig(env, agentId, 'discord');
      const dcConfig = _requireDiscordConfig(cc.config);
      const expiredText = _formatAgentMessage(agentName, message.body) + '\n\n⏰ Options expired';
      await editDiscordMessage(dcConfig, dcMsgId, expiredText, []);
    }
  }
}

export async function expirePreviousOptions(
  env: Env,
  agentId: string,
  sessionId: string | null,
  excludeMessageId: string
): Promise<void> {
  const sessionClause = sessionId
    ? 'AND session_id = ?'
    : 'AND session_id IS NULL';
  const binds = sessionId
    ? [agentId, excludeMessageId, sessionId, excludeMessageId]
    : [agentId, excludeMessageId, excludeMessageId];
  const rows = await env.DB
    .prepare(
      `SELECT * FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND id != ? ${sessionClause} AND status IN ('sent', 'delivered', 'read') AND json_extract(metadata, '$.options') IS NOT NULL AND created_at < (SELECT created_at FROM messages WHERE id = ?) ORDER BY created_at DESC`
    )
    .bind(...binds)
    .all<MessageRow>();
  for (const row of rows.results ?? []) {
    await expireMessageOptions(env, agentId, row);
  }
}

export function resolveChannelRouting(routingJson: string, priority: string): Channel | undefined {
  try {
    const routing = JSON.parse(routingJson) as Record<string, string>;
    const ch = routing[priority];
    if (ch && ['discord', 'telegram', 'email', 'api'].includes(ch)) {
      return ch as Channel;
    }
  } catch { /* ignore */ }
  return undefined;
}

/** Auto-create a Telegram forum topic for this agent if use_topics is set. */
export async function ensureTopicForAgent(env: Env, agentId: string, channelConfig: { channel: Channel; config: Record<string, unknown> }): Promise<void> {
  if (channelConfig.channel !== 'telegram') return;
  const cfg = channelConfig.config;
  if (!cfg['use_topics'] || cfg['message_thread_id']) return;
  const tgCfg = _requireTelegramConfig(cfg);
  const agentName = await fetchAgentName(env, agentId) ?? 'agent';
  try {
    const threadId = await createForumTopic(tgCfg.bot_token, tgCfg.chat_id, agentName);
    cfg['message_thread_id'] = threadId;
    // Persist the thread ID so future sends reuse it
    await env.DB
      .prepare('UPDATE channel_configs SET config = ? WHERE agent_id = ? AND channel = ?')
      .bind(JSON.stringify(cfg), agentId, 'telegram')
      .run();
  } catch {
    // Topic creation failed (group may not support topics) — deliver without thread
  }
}

/** Auto-update session status based on message characteristics. Fire-and-forget. */
export async function inferSessionStatus(
  env: Env,
  agentId: string,
  sessionId: string | null,
  mode: string,
  priority: string,
  body: string,
): Promise<void> {
  if (!sessionId) return;
  let status: string;
  let statusText: string | null = null;
  if (mode === 'blocking') {
    status = 'waiting';
    statusText = 'Waiting for boss reply';
  } else if (priority === 'critical' || priority === 'high') {
    status = 'waiting';
    statusText = body.slice(0, 100);
  } else {
    status = 'working';
    statusText = body.slice(0, 100);
  }
  await env.DB
    .prepare("UPDATE sessions SET status = ?, status_text = ?, last_seen_at = datetime('now') WHERE id = ? AND agent_id = ?")
    .bind(status, statusText, sessionId, agentId)
    .run();
}

export function extractTelegramMessageId(metadata: string | null): number | undefined {
  const meta = safeParse(metadata);
  if (!meta || typeof meta !== 'object') return undefined;
  const record = meta as Record<string, unknown>;
  // Flat key: set by delivery handler (agent_to_boss messages)
  const flat = record['telegram_message_id'];
  if (typeof flat === 'number') return flat;
  // Nested key: raw Telegram payload stored by webhook (boss_to_agent messages)
  const msg = record['message'];
  if (msg && typeof msg === 'object') {
    const id = (msg as Record<string, unknown>)['message_id'];
    if (typeof id === 'number') return id;
  }
  return undefined;
}
