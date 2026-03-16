// Channel delivery functions: format, send, retry for Discord and Telegram.
// Exports delivery helpers used by messages router.
// Depends on channel adapters, types, and delay from message-helpers.

import type { Channel, DiscordChannelConfig, TelegramChannelConfig } from '../types';
import { sendDiscordMessage } from '../channels/discord';
import {
  escapeHtml,
  formatTelegramAgentMessage,
  isImageUrl,
  sendTelegramDocument,
  sendTelegramMessage,
  sendTelegramPhoto,
} from '../channels/telegram';
import { delay } from './message-helpers';

export type DeliveryResult = { delivered: false } | { delivered: true; telegramMessageId?: number };

export function formatAgentMessage(name: string, body: string): string {
  return `[${name}] ${body}`;
}

export function requireDiscordConfig(config: Record<string, unknown>): DiscordChannelConfig {
  const channelId = config['channel_id'];
  const token = config['bot_token'];
  if (typeof channelId !== 'string' || typeof token !== 'string') {
    throw new Error('discord config malformed');
  }
  return { channel_id: channelId, bot_token: token };
}

export function requireTelegramConfig(config: Record<string, unknown>): TelegramChannelConfig {
  const chatId = config['chat_id'];
  const token = config['bot_token'];
  if (typeof chatId !== 'string' || typeof token !== 'string') {
    throw new Error('telegram config malformed');
  }
  return { chat_id: chatId, bot_token: token };
}

export async function deliverReply(
  channel: Channel,
  config: Record<string, unknown>,
  agentName: string,
  body: string,
  replyToTelegramId?: number,
): Promise<DeliveryResult> {
  if (channel === 'discord') {
    await sendDiscordMessage(requireDiscordConfig(config), formatAgentMessage(agentName, body));
    return { delivered: true };
  }
  if (channel === 'telegram') {
    const tgBody = formatTelegramAgentMessage(agentName, body);
    const telegramMessageId = await sendTelegramMessage(requireTelegramConfig(config), tgBody, { replyToMessageId: replyToTelegramId });
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
): Promise<DeliveryResult> {
  if (channel === 'discord') {
    const discordBody = formatAgentMessage(agentName, body);
    await sendDiscordMessage(requireDiscordConfig(config), fileUrl ? `${discordBody}\n${fileUrl}` : discordBody);
    return { delivered: true };
  }
  if (channel === 'telegram') {
    const tgConfig = requireTelegramConfig(config);
    const tgBody = formatTelegramAgentMessage(agentName, body);
    let telegramMessageId: number | undefined;
    if (fileUrl) {
      const caption = escapeHtml(`[${agentName}] ${body}`);
      if (isImageUrl(fileUrl)) {
        telegramMessageId = await sendTelegramPhoto(tgConfig, fileUrl, caption);
      } else {
        telegramMessageId = await sendTelegramDocument(tgConfig, fileUrl, caption);
      }
    } else {
      telegramMessageId = await sendTelegramMessage(tgConfig, tgBody, { inlineKeyboard });
    }
    return { delivered: true, telegramMessageId };
  }
  return { delivered: false };
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
