/**
 * Helper functions for message options and expiry.
 * Handles parsing options, building keyboards, and expiring old message options.
 */

import type { Channel, Env, MessageRow } from '../types';
import { createForumTopic, editMessageReplyMarkup } from '../channels/telegram';
import { createDiscordThread, editDiscordMessage } from '../channels/discord';
import { 
  requireTelegramConfig as _requireTelegramConfig, 
  requireDiscordConfig as _requireDiscordConfig, 
  formatAgentMessage as _formatAgentMessage 
} from './delivery';
import { selectChannelConfig, fetchAgentName } from './message-queries';
import { extractTelegramMessageId } from './message-helpers';

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

/** Auto-create a Discord thread for this session if use_threads is enabled. */
export async function ensureThreadForSession(
  env: Env,
  agentId: string,
  sessionId: string | null,
  channelConfig: { channel: Channel; config: Record<string, unknown> },
  discordMessageId: string | undefined,
): Promise<string | undefined> {
  if (channelConfig.channel !== 'discord') return undefined;
  const cfg = channelConfig.config;
  if (!cfg['use_threads']) return undefined;
  if (!sessionId) return undefined;

  const session = await env.DB
    .prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ discord_thread_id: string | null }>();
  if (session?.discord_thread_id) return session.discord_thread_id;
  if (!discordMessageId) return undefined;

  const botToken = cfg['bot_token'] as string | undefined;
  const channelId = cfg['channel_id'] as string | undefined;
  if (!botToken || !channelId) return undefined;

  const agentName = await fetchAgentName(env, agentId) ?? 'agent';
  const sessionRow = await env.DB
    .prepare('SELECT label, branch FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ label: string | null; branch: string | null }>();
  const threadName = sessionRow?.label ?? sessionRow?.branch ?? `${agentName}-session`;

  try {
    const threadId = await createDiscordThread(botToken, channelId, discordMessageId, threadName);
    await env.DB
      .prepare('UPDATE sessions SET discord_thread_id = ? WHERE id = ?')
      .bind(threadId, sessionId)
      .run();
    return threadId;
  } catch {
    // Thread creation failed — deliver without thread
    return undefined;
  }
}
