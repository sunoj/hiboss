/**
 * Helper functions for message options and expiry.
 * Handles parsing options, building keyboards, and expiring old message options.
 */

import type { Channel, Env, MessageRow } from '../types';
import { createForumTopic, editMessageReplyMarkup, removeInlineKeyboard } from '../channels/telegram';
import { createDiscordThread, addDiscordThreadMember, editDiscordMessage } from '../channels/discord';
import { 
  requireTelegramConfig as _requireTelegramConfig, 
  requireDiscordConfig as _requireDiscordConfig, 
  formatAgentMessage as _formatAgentMessage 
} from './delivery';
import { selectChannelConfig, fetchAgentName } from './message-queries';
import { extractTelegramMessageId, replyTargetSession } from './message-helpers';
import { notifyAgentCallback } from '../notify';
import { createMessageId, insertMessageWithEvent } from '../session-events';

const MAX_MESSAGE_OPTIONS = 5;
const OPTIONS_ERROR = 'options must be an array of 1 to 5 non-empty unique strings';

export type OptionsParseResult =
  | { ok: true; value: string[] | undefined }
  | { ok: false; error: string };

export function parseOptions(value: unknown): OptionsParseResult {
  if (value === undefined) return { ok: true, value: undefined };
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_MESSAGE_OPTIONS) {
    return { ok: false, error: OPTIONS_ERROR };
  }
  if (!value.every((option): option is string => typeof option === 'string')) {
    return { ok: false, error: OPTIONS_ERROR };
  }
  const options = value.map((option) => option.trim());
  if (options.some((option) => !option) || new Set(options).size !== options.length) {
    return { ok: false, error: OPTIONS_ERROR };
  }
  return { ok: true, value: options };
}

export function buildInlineKeyboard(messageId: string, options: string[]): { text: string; callback_data: string }[][] {
  return options.map((opt) => [{ text: opt, callback_data: `${messageId.slice(0, 12)}:${opt}` }]);
}

export async function expireMessageOptions(env: Env, agentId: string, message: MessageRow): Promise<void> {
  // 1. Update DB: set status to expired, mark options_expired in metadata
  const meta = message.metadata ? JSON.parse(message.metadata) as Record<string, unknown> : {};
  const defaultOption = getDefaultOption(meta);
  if (defaultOption) {
    await autoResolveDefaultOption(env, agentId, message, meta, defaultOption);
    return;
  }
  meta['options_expired'] = true;
  delete meta['actions'];
  await env.DB
    .prepare("UPDATE messages SET status = 'expired', metadata = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(JSON.stringify(meta), message.id)
    .run();
  
  // 2. Clean up channel inline keyboards
  await editExpiredChannelMessage(env, agentId, message, meta, '⏰ Options expired');
}

function getDefaultOption(meta: Record<string, unknown>): string | null {
  const defaultOption = meta['default_option'];
  const options = meta['options'];
  if (typeof defaultOption !== 'string' || defaultOption.trim() === '') return null;
  if (!Array.isArray(options) || !options.every((option): option is string => typeof option === 'string')) {
    return null;
  }
  return options.includes(defaultOption) ? defaultOption : null;
}

async function autoResolveDefaultOption(
  env: Env,
  agentId: string,
  message: MessageRow,
  meta: Record<string, unknown>,
  defaultOption: string,
): Promise<void> {
  meta['options_expired'] = true;
  delete meta['actions'];
  const claimed = await env.DB
    .prepare(
      "UPDATE messages SET status = 'replied', metadata = ?, updated_at = datetime('now') WHERE id = ? AND status IN ('sent', 'delivered', 'read') RETURNING id"
    )
    .bind(JSON.stringify(meta), message.id)
    .first<{ id: string }>();
  if (!claimed) return;
  const inserted = await insertMessageWithEvent(
    env,
    'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, reply_to, metadata, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
    [createMessageId(), agentId, 'boss_to_agent', 'async', 'api', defaultOption, 'sent', 'normal', message.id, JSON.stringify({ auto_default: true, source: 'api' }), replyTargetSession(message)],
    replyTargetSession(message),
  );
  if (!inserted) return;
  // Best-effort notifications: the default is already durably recorded above, so a failed
  // agent callback / channel edit (e.g. unreachable URL) must not throw out of the cron path.
  try {
    await notifyAgentCallback(env, agentId, inserted);
    await withdrawResolvedOptions(env, agentId, { ...message, metadata: JSON.stringify(meta) }, defaultOption);
    await editExpiredChannelMessage(env, agentId, message, meta, `⏰ Timed out — default selected: ${defaultOption}`);
  } catch {
    // swallow: resolution persisted; downstream fan-out is best-effort
  }
}

async function editExpiredChannelMessage(
  env: Env,
  agentId: string,
  message: MessageRow,
  meta: Record<string, unknown>,
  notice: string,
): Promise<void> {
  const agentName = await fetchAgentName(env, agentId) ?? 'agent';
  if (message.channel === 'telegram') {
    const tgMsgId = extractTelegramMessageId(message.metadata);
    if (tgMsgId) {
      const cc = await selectChannelConfig(env, agentId, 'telegram');
      const tgConfig = _requireTelegramConfig(cc.config);
      const expiredText = _formatAgentMessage(agentName, message.body) + `\n\n${notice}`;
      await editMessageReplyMarkup(tgConfig.bot_token, tgConfig.chat_id, tgMsgId, expiredText);
    }
  } else if (message.channel === 'discord') {
    const dcMsgId = meta['discord_message_id'] as string | undefined;
    if (dcMsgId) {
      const cc = await selectChannelConfig(env, agentId, 'discord');
      const dcConfig = _requireDiscordConfig(cc.config);
      const expiredText = _formatAgentMessage(agentName, message.body) + `\n\n${notice}`;
      await editDiscordMessage(dcConfig, dcMsgId, expiredText, []);
    }
  }
}

export async function withdrawResolvedOptions(
  env: Env,
  agentId: string,
  message: MessageRow,
  selectedOption: string,
): Promise<void> {
  const metadata = message.metadata ? JSON.parse(message.metadata) as Record<string, unknown> : {};
  metadata['options_resolved'] = true;
  metadata['selected_option'] = selectedOption;
  delete metadata['actions'];
  await env.DB.prepare("UPDATE messages SET metadata = ?, updated_at = datetime('now') WHERE id = ?")
    .bind(JSON.stringify(metadata), message.id).run();
  await Promise.allSettled([
    removeTelegramOptions(env, agentId, metadata),
    removeDiscordOptions(env, agentId, message, metadata),
  ]);
}

async function removeTelegramOptions(
  env: Env,
  agentId: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  const messageId = metadata['telegram_message_id'];
  if (typeof messageId !== 'number') return;
  const channel = await selectChannelConfig(env, agentId, 'telegram');
  const config = _requireTelegramConfig(channel.config);
  await removeInlineKeyboard(config.bot_token, config.chat_id, messageId);
}

async function removeDiscordOptions(
  env: Env,
  agentId: string,
  message: MessageRow,
  metadata: Record<string, unknown>,
): Promise<void> {
  const messageId = metadata['discord_message_id'];
  if (typeof messageId !== 'string') return;
  const channel = await selectChannelConfig(env, agentId, 'discord');
  const effectiveConfig = await resolveDiscordConfig(env, message, channel.config);
  await editDiscordMessage(_requireDiscordConfig(effectiveConfig), messageId, undefined, []);
}

async function resolveDiscordConfig(
  env: Env,
  message: MessageRow,
  config: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (!message.session_id || !config['use_threads']) return config;
  const session = await env.DB.prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(message.session_id).first<{ discord_thread_id: string | null }>();
  if (!session?.discord_thread_id) return config;
  return { ...config, channel_id: session.discord_thread_id, thread_id: session.discord_thread_id };
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
  messageBody?: string,
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

  const sessionRow = await env.DB
    .prepare('SELECT label, branch FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ label: string | null; branch: string | null }>();
  // Thread title: "repo/branch: first message summary" (max 100 chars for Discord)
  const prefix = sessionRow?.label ?? sessionRow?.branch;
  const summary = messageBody ? messageBody.split('\n')[0].slice(0, 60) : undefined;
  const threadName = prefix && summary
    ? `${prefix}: ${summary}`.slice(0, 100)
    : prefix ?? summary ?? `${await fetchAgentName(env, agentId) ?? 'agent'}-session`;

  try {
    const threadId = await createDiscordThread(botToken, channelId, discordMessageId, threadName);
    await env.DB
      .prepare('UPDATE sessions SET discord_thread_id = ? WHERE id = ?')
      .bind(threadId, sessionId)
      .run();
    // Add boss(es) to thread so they get notifications (bot-created threads only include the bot)
    const bosses = await env.DB
      .prepare('SELECT b.discord_user_id FROM bosses b JOIN boss_agent_access ba ON ba.boss_id = b.id WHERE ba.agent_id = ? AND b.discord_user_id IS NOT NULL')
      .bind(agentId)
      .all<{ discord_user_id: string }>();
    for (const boss of bosses.results ?? []) {
      await addDiscordThreadMember(botToken, threadId, boss.discord_user_id).catch(() => {});
    }
    return threadId;
  } catch {
    // Thread creation failed — deliver without thread
    return undefined;
  }
}
