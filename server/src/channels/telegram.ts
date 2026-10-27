// Telegram adapter that issues sendMessage calls to a bot chat.
// Exports a sender helper that relies on chat_id and bot token config.
// Depends on global fetch and the shared config typings.

import type { TelegramChannelConfig } from '../types';

export { sendTelegramMediaGroup } from './telegram-media';

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

export function formatTelegramAttachmentCaption(agentName: string, body: string): string {
  return escapeHtml(`[${agentName}] ${body}`);
}

export async function sendTelegramMessage(
  config: TelegramChannelConfig, content: string, options?: SendOptions,
): Promise<number | undefined> {
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
  applySendOptions(payload, threadId, options);
  const response = await postTelegramHtml(config.bot_token, 'sendMessage', payload, 'text', 'send');
  return readMessageId(response);
}

export async function sendTelegramTyping(
  botToken: string, chatId: string, messageThreadId?: number,
): Promise<void> {
  const payload: Record<string, unknown> = { chat_id: chatId, action: 'typing' };
  if (messageThreadId) payload.message_thread_id = messageThreadId;
  await postTelegram(botToken, 'sendChatAction', payload);
}

export async function answerCallbackQuery(
  botToken: string, callbackQueryId: string, text: string,
): Promise<void> {
  await postTelegram(botToken, 'answerCallbackQuery', { callback_query_id: callbackQueryId, text });
}

export async function editTelegramMessageText(
  config: TelegramChannelConfig, messageId: number, content: string,
): Promise<void> {
  await editTelegramMessage(config, messageId, content, 'editMessageText', 'text');
}

export async function editTelegramCaption(
  config: TelegramChannelConfig, messageId: number, content: string,
): Promise<void> {
  await editTelegramMessage(config, messageId, content, 'editMessageCaption', 'caption');
}

export async function editMessageReplyMarkup(
  botToken: string, chatId: string, messageId: number, text: string,
): Promise<void> {
  await postTelegram(botToken, 'editMessageText', {
    chat_id: chatId,
    message_id: messageId,
    text,
    reply_markup: { inline_keyboard: [] },
  });
}

export async function removeInlineKeyboard(
  botToken: string, chatId: string, messageId: number,
): Promise<void> {
  await postTelegram(botToken, 'editMessageReplyMarkup', {
    chat_id: chatId,
    message_id: messageId,
    reply_markup: { inline_keyboard: [] },
  });
}

export async function sendTelegramPhoto(
  config: TelegramChannelConfig, photoUrl: string, caption?: string, options?: SendOptions,
): Promise<number | undefined> {
  return sendTelegramAttachment(config, 'photo', photoUrl, caption, options);
}

export async function sendTelegramDocument(
  config: TelegramChannelConfig, docUrl: string, caption?: string, options?: SendOptions,
): Promise<number | undefined> {
  return sendTelegramAttachment(config, 'document', docUrl, caption, options);
}

async function sendTelegramAttachment(
  config: TelegramChannelConfig, kind: 'photo' | 'document', url: string,
  caption?: string, options?: SendOptions,
): Promise<number | undefined> {
  if (!config.bot_token || !config.chat_id) {
    throw new Error('telegram config incomplete');
  }
  const threadId = options?.messageThreadId ?? config.message_thread_id;
  await sendTelegramTyping(config.bot_token, config.chat_id, threadId);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    [kind]: url,
  };
  if (caption) {
    payload.caption = caption;
    payload.parse_mode = 'HTML';
  }
  applySendOptions(payload, threadId, options);
  const method = kind === 'photo' ? 'sendPhoto' : 'sendDocument';
  let response = await postTelegram(config.bot_token, method, payload);
  if (!response.ok) {
    if (kind === 'photo') throw new Error(`telegram sendPhoto failed ${response.status}`);
    // Fallback: if sendDocument fails, send URL as text message
    const label = caption ? stripHtmlTags(caption) : 'Attachment';
    const fallbackPayload: Record<string, unknown> = {
      chat_id: config.chat_id,
      text: `${label}\n📎 ${url}`,
    };
    applySendOptions(fallbackPayload, threadId, options);
    response = await postTelegram(config.bot_token, 'sendMessage', fallbackPayload);
    if (!response.ok) {
      throw new Error(`telegram sendDocument fallback failed ${response.status}`);
    }
  }
  return readMessageId(response);
}

export function isImageUrl(url: string): boolean {
  const lower = url.toLowerCase().split('?')[0];
  return /\.(jpg|jpeg|png|gif|webp|bmp)$/.test(lower);
}

export async function setTelegramReaction(
  botToken: string, chatId: string, messageId: number, emoji: string,
): Promise<void> {
  await postTelegram(botToken, 'setMessageReaction', {
    chat_id: chatId,
    message_id: messageId,
    reaction: [{ type: 'emoji', emoji }],
  });
}

export async function createForumTopic(botToken: string, chatId: string, name: string): Promise<number> {
  const response = await postTelegram(botToken, 'createForumTopic', {
    chat_id: chatId, name: name.slice(0, 128),
  });
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

async function editTelegramMessage(
  config: TelegramChannelConfig,
  messageId: number,
  content: string,
  method: 'editMessageText' | 'editMessageCaption',
  contentKey: 'text' | 'caption',
): Promise<void> {
  await postTelegramHtml(config.bot_token, method, {
    chat_id: config.chat_id, message_id: messageId, [contentKey]: content, parse_mode: 'HTML',
  }, contentKey, 'edit');
}

async function postTelegramHtml(
  botToken: string, method: string, payload: Record<string, unknown>,
  contentKey: 'text' | 'caption', action: 'send' | 'edit',
): Promise<Response> {
  let response = await postTelegram(botToken, method, payload);
  // Fall back to plain text if HTML parsing fails
  if (!response.ok) {
    const errorBody = await response.text();
    if (errorBody.includes("can't parse entities")) {
      payload = { ...payload, parse_mode: undefined, [contentKey]: stripHtmlTags(String(payload[contentKey])) };
      response = await postTelegram(botToken, method, payload);
    }
    if (!response.ok) {
      const finalError = errorBody.includes("can't parse entities") ? await response.text() : errorBody;
      throw new Error(`telegram ${action} failed ${response.status} ${finalError}`);
    }
  }
  return response;
}

function postTelegram(botToken: string, method: string, payload: Record<string, unknown>): Promise<Response> {
  return fetch(`https://api.telegram.org/bot${encodeURIComponent(botToken)}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
}

function applySendOptions(
  payload: Record<string, unknown>, threadId: number | undefined, options?: SendOptions,
): void {
  if (threadId) payload.message_thread_id = threadId;
  if (options?.replyToMessageId) payload.reply_parameters = { message_id: options.replyToMessageId };
  if (options?.inlineKeyboard) payload.reply_markup = { inline_keyboard: options.inlineKeyboard };
}

async function readMessageId(response: Response): Promise<number | undefined> {
  try {
    const result = await response.json() as { result?: { message_id?: number } };
    return result?.result?.message_id;
  } catch {
    return undefined;
  }
}
