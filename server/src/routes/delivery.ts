// Channel delivery functions: format, send, retry for Discord, Telegram, and API.
// Exports delivery helpers used by messages router.
// Depends on channel adapters, types, and delay from message-helpers.

import type { Channel, DiscordChannelConfig, Env, TelegramChannelConfig } from '../types';
import { sendDiscordMessage, sendDiscordTyping, type DiscordSendOptions } from '../channels/discord';
import {
  formatTelegramAttachmentCaption,
  formatTelegramAgentMessage,
  isImageUrl,
  sendTelegramDocument,
  sendTelegramMessage,
  sendTelegramPhoto,
} from '../channels/telegram';
import { delay } from './message-helpers';
import { fetchTelegramTopicIdForSession } from './session-channels';

export type DeliveryResult = { delivered: false } | { delivered: true; telegramMessageId?: number; discordMessageId?: string };

export function formatAgentMessage(name: string, body: string): string {
  return `[${name}] ${body}`;
}

export function getDeliveryErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'delivery failure';
}

export async function persistDeliveryFailure(env: Env, messageId: string, errorMessage: string): Promise<void> {
  await env.DB.prepare(
    "UPDATE messages SET metadata = json_set(COALESCE(metadata, '{}'), '$.delivery_error', ?), updated_at = datetime('now') WHERE id = ?"
  ).bind(errorMessage, messageId).run();
}

export function requireDiscordConfig(config: Record<string, unknown>): DiscordChannelConfig {
  const avatarUrl = typeof config['avatar_url'] === 'string' ? config['avatar_url'] : undefined;
  const webhookUrl = config['webhook_url'];
  const channelId = typeof config['channel_id'] === 'string' ? config['channel_id'] : undefined;
  const botToken = typeof config['bot_token'] === 'string' ? config['bot_token'] : undefined;
  const threadId = typeof config['thread_id'] === 'string' ? config['thread_id'] : undefined;
  if (typeof webhookUrl === 'string') {
    // Webhook mode — also keep bot_token/channel_id for reactions, thread_id for thread routing
    return { webhook_url: webhookUrl, avatar_url: avatarUrl, bot_token: botToken, channel_id: channelId, thread_id: threadId };
  }
  if (!channelId || !botToken) {
    throw new Error('discord config malformed');
  }
  return { channel_id: channelId, bot_token: botToken };
}

export function requireTelegramConfig(config: Record<string, unknown>): TelegramChannelConfig {
  const chatId = config['chat_id'];
  const token = config['bot_token'];
  if (typeof chatId !== 'string' || typeof token !== 'string') {
    throw new Error('telegram config malformed');
  }
  const result: TelegramChannelConfig = { chat_id: chatId, bot_token: token };
  if (typeof config['message_thread_id'] === 'number') {
    result.message_thread_id = config['message_thread_id'];
  }
  if (typeof config['use_topics'] === 'boolean') {
    result.use_topics = config['use_topics'];
  }
  return result;
}

export async function deliverReply(
  channel: Channel,
  config: Record<string, unknown>,
  agentName: string,
  body: string,
  replyToTelegramId?: number,
  agentAvatarUrl?: string,
  env?: Env,
  sessionId?: string | null,
): Promise<DeliveryResult> {
  if (channel === 'api') {
    return { delivered: true };
  }
  if (channel === 'discord') {
    const dc = requireDiscordConfig(config);
    const opts = discordOptions(dc, agentName, agentAvatarUrl);
    await sendDiscordTyping(dc);
    const result = await sendDiscordMessage(dc, opts ? body : formatAgentMessage(agentName, body), opts);
    return { delivered: true, discordMessageId: result.messageId };
  }
  if (channel === 'telegram') {
    const tgBody = formatTelegramAgentMessage(agentName, body);
    const messageThreadId = await fetchSessionTelegramTopicId(env, sessionId);
    const telegramMessageId = await sendTelegramMessage(requireTelegramConfig(config), tgBody, {
      replyToMessageId: replyToTelegramId,
      messageThreadId,
    });
    return { delivered: true, telegramMessageId };
  }
  return { delivered: false };
}

export async function deliverToChannelWithOptions(
  channel: Channel,
  config: Record<string, unknown>,
  agentName: string,
  body: string,
  inlineKeyboard?: { text: string; callback_data: string }[][],
  fileUrl?: string,
  agentAvatarUrl?: string,
  env?: Env,
  sessionId?: string | null,
): Promise<DeliveryResult> {
  if (channel === 'api') {
    return { delivered: true };
  }
  if (channel === 'discord') {
    const dc = requireDiscordConfig(config);
    const opts = discordOptions(dc, agentName, agentAvatarUrl);
    const baseText = opts ? body : formatAgentMessage(agentName, body);
    const components = inlineKeyboard ? inlineKeyboardToDiscordComponents(inlineKeyboard) : undefined;
    const content = formatDiscordContent(baseText, fileUrl);
    const sendOptions = buildDiscordSendOptions(opts, components, fileUrl);
    await sendDiscordTyping(dc);
    const result = await sendDiscordMessage(dc, content, sendOptions);
    return { delivered: true, discordMessageId: result.messageId };
  }
  if (channel === 'telegram') {
    const tgConfig = requireTelegramConfig(config);
    const tgBody = formatTelegramAgentMessage(agentName, body);
    const messageThreadId = await fetchSessionTelegramTopicId(env, sessionId);
    let telegramMessageId: number | undefined;
    if (fileUrl) {
      const caption = formatTelegramAttachmentCaption(agentName, body);
      if (isImageUrl(fileUrl)) {
        telegramMessageId = await sendTelegramPhoto(tgConfig, fileUrl, caption, { messageThreadId });
      } else {
        telegramMessageId = await sendTelegramDocument(tgConfig, fileUrl, caption, { messageThreadId });
      }
    } else {
      telegramMessageId = await sendTelegramMessage(tgConfig, tgBody, { inlineKeyboard, messageThreadId });
    }
    return { delivered: true, telegramMessageId };
  }
  return { delivered: false };
}

function inlineKeyboardToDiscordComponents(keyboard: { text: string; callback_data: string }[][]): unknown[] {
  return keyboard.map((row) => ({
    type: 1,
    components: row.map((btn) => ({
      type: 2,
      style: 1,
      label: btn.text.slice(0, 80),
      custom_id: btn.callback_data.slice(0, 100),
    })),
  }));
}

function sanitizeDiscordUsername(name: string): string {
  // Discord forbids "discord", "clyde", "webhook" (case-insensitive) in webhook usernames
  return name.replace(/discord/gi, 'dscrd').replace(/clyde/gi, 'clyd').replace(/webhook/gi, 'wbhk');
}

function discordOptions(config: DiscordChannelConfig, agentName: string, avatarUrl?: string): DiscordSendOptions | undefined {
  if (!config.webhook_url) return undefined;
  return { username: sanitizeDiscordUsername(agentName).slice(0, 80), avatarUrl: avatarUrl ?? config.avatar_url };
}

function buildDiscordSendOptions(
  baseOptions: DiscordSendOptions | undefined,
  components?: unknown[],
  fileUrl?: string,
): DiscordSendOptions | undefined {
  const options: DiscordSendOptions = baseOptions ? { ...baseOptions } : {};
  if (components) options.components = components;
  if (fileUrl) {
    if (isImageUrl(fileUrl)) {
      options.embeds = [{ image: { url: fileUrl } }];
    } else {
      options.fileUrl = fileUrl;
    }
  }
  return Object.keys(options).length > 0 ? options : undefined;
}

function formatDiscordContent(text: string, fileUrl?: string): string {
  if (!fileUrl || isImageUrl(fileUrl)) return text;
  const attachmentLabel = getDiscordAttachmentLabel(fileUrl);
  return text ? `${text}\nAttachment: ${attachmentLabel}` : `Attachment: ${attachmentLabel}`;
}

function getDiscordAttachmentLabel(fileUrl: string): string {
  try {
    const candidate = new URL(fileUrl).pathname.split('/').filter(Boolean).pop();
    if (candidate) return decodeURIComponent(candidate);
  } catch {
    return 'attachment';
  }
  return 'attachment';
}

export async function deliverWithRetry<T>(
  fn: () => Promise<T>,
  maxRetries: number = 1,
  delayMs: number = 2000,
): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;
      if (attempt < maxRetries) {
        await delay(delayMs);
      }
    }
  }
  throw lastError;
}

async function fetchSessionTelegramTopicId(env?: Env, sessionId?: string | null): Promise<number | undefined> {
  if (!env || !sessionId) return undefined;
  return fetchTelegramTopicIdForSession(env, sessionId);
}
