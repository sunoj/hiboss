// Telegram adapter that issues sendMessage calls to a bot chat.
// Exports a sender helper that relies on chat_id and bot token config.
// Depends on global fetch and the shared config typings.

import type { TelegramChannelConfig } from '../types';

type SendOptions = {
  replyToMessageId?: number;
  inlineKeyboard?: { text: string; callback_data: string }[][];
  messageThreadId?: number;
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
  const threadId = options?.messageThreadId ?? config.message_thread_id;
  await sendTelegramTyping(config.bot_token, config.chat_id, threadId);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    text: content,
    parse_mode: 'HTML',
  };
  if (threadId) payload.message_thread_id = threadId;
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
      const finalError = errorBody.includes("can't parse entities") ? await response.text() : errorBody;
      throw new Error(`telegram send failed ${response.status} ${finalError}`);
    }
  }
  try {
    const result = await response.json() as { result?: { message_id?: number } };
    return result?.result?.message_id;
  } catch {
    return undefined;
  }
}

export async function sendTelegramTyping(botToken: string, chatId: string, messageThreadId?: number): Promise<void> {
  const payload: Record<string, unknown> = { chat_id: chatId, action: 'typing' };
  if (messageThreadId) payload.message_thread_id = messageThreadId;
  await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/sendChatAction`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
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

export async function editTelegramMessageText(config: TelegramChannelConfig, messageId: number, content: string): Promise<void> {
  let payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    message_id: messageId,
    text: content,
    parse_mode: 'HTML',
  };
  let response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/editMessageText`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    }
  );
  if (!response.ok) {
    const errorBody = await response.text();
    if (errorBody.includes("can't parse entities")) {
      payload = { ...payload, parse_mode: undefined, text: stripHtmlTags(content) };
      response = await fetch(
        `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/editMessageText`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }
      );
    }
    if (!response.ok) {
      const finalError = errorBody.includes("can't parse entities") ? await response.text() : errorBody;
      throw new Error(`telegram edit failed ${response.status} ${finalError}`);
    }
  }
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

export async function removeInlineKeyboard(botToken: string, chatId: string, messageId: number): Promise<void> {
  await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/editMessageReplyMarkup`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id: chatId,
        message_id: messageId,
        reply_markup: { inline_keyboard: [] },
      }),
    }
  );
}

export async function sendTelegramPhoto(config: TelegramChannelConfig, photoUrl: string, caption?: string, options?: SendOptions): Promise<number | undefined> {
  if (!config.bot_token || !config.chat_id) {
    throw new Error('telegram config incomplete');
  }
  const threadId = options?.messageThreadId ?? config.message_thread_id;
  await sendTelegramTyping(config.bot_token, config.chat_id, threadId);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    photo: photoUrl,
  };
  if (threadId) payload.message_thread_id = threadId;
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
  const threadId = options?.messageThreadId ?? config.message_thread_id;
  await sendTelegramTyping(config.bot_token, config.chat_id, threadId);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    document: docUrl,
  };
  if (threadId) payload.message_thread_id = threadId;
  if (caption) {
    payload.caption = caption;
    payload.parse_mode = 'HTML';
  }
  if (options?.replyToMessageId) {
    payload.reply_parameters = { message_id: options.replyToMessageId };
  }
  let response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendDocument`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) }
  );
  // Fallback: if sendDocument fails, send URL as text message
  if (!response.ok) {
    const label = caption ? stripHtmlTags(caption) : 'Attachment';
    const fallbackPayload: Record<string, unknown> = {
      chat_id: config.chat_id,
      text: `${label}\n📎 ${docUrl}`,
    };
    if (threadId) fallbackPayload.message_thread_id = threadId;
    if (options?.replyToMessageId) {
      fallbackPayload.reply_parameters = { message_id: options.replyToMessageId };
    }
    response = await fetch(
      `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendMessage`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(fallbackPayload) }
    );
    if (!response.ok) {
      throw new Error(`telegram sendDocument fallback failed ${response.status}`);
    }
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

export async function createForumTopic(botToken: string, chatId: string, name: string): Promise<number> {
  const response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/createForumTopic`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, name: name.slice(0, 128) }),
    }
  );
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`telegram createForumTopic failed ${response.status} ${body}`);
  }
  const result = await response.json() as { result?: { message_thread_id?: number } };
  const threadId = result?.result?.message_thread_id;
  if (!threadId) throw new Error('createForumTopic returned no thread id');
  return threadId;
}

function stripHtmlTags(html: string): string {
  return html.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
}
