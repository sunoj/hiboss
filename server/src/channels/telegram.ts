// Telegram adapter that issues sendMessage calls to a bot chat.
// Exports a sender helper that relies on chat_id and bot token config.
// Depends on global fetch and the shared config typings.

import type { TelegramChannelConfig } from '../types';

type SendOptions = {
  replyToMessageId?: number;
  inlineKeyboard?: { text: string; callback_data: string }[][];
};

export function escapeHtml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

export function formatTelegramAgentMessage(agentName: string, body: string): string {
  return `<b>[${escapeHtml(agentName)}]</b> ${escapeHtml(body)}`;
}

export async function sendTelegramMessage(config: TelegramChannelConfig, content: string, options?: SendOptions): Promise<number | undefined> {
  if (!config.bot_token || !config.chat_id) {
    throw new Error('telegram config incomplete');
  }
  await sendTelegramTyping(config.bot_token, config.chat_id);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    text: content,
    parse_mode: 'HTML',
  };
  if (options?.replyToMessageId) {
    payload.reply_parameters = { message_id: options.replyToMessageId };
  }
  if (options?.inlineKeyboard) {
    payload.reply_markup = { inline_keyboard: options.inlineKeyboard };
  }
  let response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendMessage`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    }
  );
  // Fall back to plain text if HTML parsing fails
  if (!response.ok) {
    const errorBody = await response.text();
    if (errorBody.includes("can't parse entities")) {
      payload.parse_mode = undefined;
      payload.text = stripHtmlTags(content);
      response = await fetch(
        `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendMessage`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }
      );
    }
    if (!response.ok) {
      throw new Error(`telegram send failed ${response.status} ${errorBody}`);
    }
  }
  try {
    const result = await response.json() as { result?: { message_id?: number } };
    return result?.result?.message_id;
  } catch {
    return undefined;
  }
}

export async function sendTelegramTyping(botToken: string, chatId: string): Promise<void> {
  await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/sendChatAction`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, action: 'typing' }),
    }
  );
}

export async function answerCallbackQuery(botToken: string, callbackQueryId: string, text: string): Promise<void> {
  await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/answerCallbackQuery`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ callback_query_id: callbackQueryId, text }),
    }
  );
}

export async function editMessageReplyMarkup(botToken: string, chatId: string, messageId: number, text: string): Promise<void> {
  await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/editMessageText`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        message_id: messageId,
        text,
        reply_markup: { inline_keyboard: [] },
      }),
    }
  );
}

export async function sendTelegramPhoto(config: TelegramChannelConfig, photoUrl: string, caption?: string, options?: SendOptions): Promise<number | undefined> {
  if (!config.bot_token || !config.chat_id) {
    throw new Error('telegram config incomplete');
  }
  await sendTelegramTyping(config.bot_token, config.chat_id);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    photo: photoUrl,
  };
  if (caption) {
    payload.caption = caption;
    payload.parse_mode = 'HTML';
  }
  if (options?.replyToMessageId) {
    payload.reply_parameters = { message_id: options.replyToMessageId };
  }
  const response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendPhoto`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }
  );
  if (!response.ok) {
    throw new Error(`telegram sendPhoto failed ${response.status}`);
  }
  try {
    const result = await response.json() as { result?: { message_id?: number } };
    return result?.result?.message_id;
  } catch { return undefined; }
}

export async function sendTelegramDocument(config: TelegramChannelConfig, docUrl: string, caption?: string, options?: SendOptions): Promise<number | undefined> {
  if (!config.bot_token || !config.chat_id) {
    throw new Error('telegram config incomplete');
  }
  await sendTelegramTyping(config.bot_token, config.chat_id);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    document: docUrl,
  };
  if (caption) {
    payload.caption = caption;
    payload.parse_mode = 'HTML';
  }
  if (options?.replyToMessageId) {
    payload.reply_parameters = { message_id: options.replyToMessageId };
  }
  const response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendDocument`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }
  );
  if (!response.ok) {
    throw new Error(`telegram sendDocument failed ${response.status}`);
  }
  try {
    const result = await response.json() as { result?: { message_id?: number } };
    return result?.result?.message_id;
  } catch { return undefined; }
}

export function isImageUrl(url: string): boolean {
  const lower = url.toLowerCase().split('?')[0];
  return /\.(jpg|jpeg|png|gif|webp|bmp)$/.test(lower);
}

export async function setTelegramReaction(botToken: string, chatId: string, messageId: number, emoji: string): Promise<void> {
  await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/setMessageReaction`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        message_id: messageId,
        reaction: [{ type: 'emoji', emoji }],
      }),
    }
  );
}

function stripHtmlTags(html: string): string {
  return html.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}
