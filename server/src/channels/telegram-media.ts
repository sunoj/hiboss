// Telegram media-group adapter for option image delivery.
// Exports sendTelegramMediaGroup for the channel delivery flow.
// Depends on TelegramChannelConfig and global fetch.

import type { TelegramChannelConfig } from '../types';

export interface TelegramMediaItem {
  url: string;
  caption: string;
}

export async function sendTelegramMediaGroup(
  config: TelegramChannelConfig,
  items: TelegramMediaItem[],
  options?: { messageThreadId?: number },
): Promise<number[]> {
  if (!config.bot_token || !config.chat_id) throw new Error('telegram config incomplete');
  if (items.length < 2 || items.length > 10) throw new Error('telegram media group requires 2 to 10 items');
  const threadId = options?.messageThreadId ?? config.message_thread_id;
  await sendTelegramTyping(config.bot_token, config.chat_id, threadId);
  const payload: Record<string, unknown> = {
    chat_id: config.chat_id,
    media: items.map((item) => ({ type: 'photo', media: item.url, caption: item.caption, parse_mode: 'HTML' })),
  };
  if (threadId) payload.message_thread_id = threadId;
  const response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendMediaGroup`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) },
  );
  if (!response.ok) throw new Error(`telegram sendMediaGroup failed ${response.status}`);
  const result = await response.json() as { result?: { message_id?: number }[] };
  return (result.result ?? []).flatMap((item) => item.message_id === undefined ? [] : [item.message_id]);
}

async function sendTelegramTyping(botToken: string, chatId: string, messageThreadId?: number): Promise<void> {
  const payload: Record<string, unknown> = { chat_id: chatId, action: 'typing' };
  if (messageThreadId) payload.message_thread_id = messageThreadId;
  await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(botToken)}/sendChatAction`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) },
  );
}
