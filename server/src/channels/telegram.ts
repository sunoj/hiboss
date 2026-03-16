// Telegram adapter that issues sendMessage calls to a bot chat.
// Exports a sender helper that relies on chat_id and bot token config.
// Depends on global fetch and the shared config typings.

import type { TelegramChannelConfig } from '../types';

export async function sendTelegramMessage(config: TelegramChannelConfig, content: string): Promise<void> {
  if (!config.bot_token || !config.chat_id) {
    throw new Error('telegram config incomplete');
  }
  await sendTelegramTyping(config.bot_token, config.chat_id);
  const response = await fetch(
    `https://api.telegram.org/bot${encodeURIComponent(config.bot_token)}/sendMessage`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: config.chat_id, text: content }),
    }
  );
  if (!response.ok) {
    const payload = await response.text();
    throw new Error(`telegram send failed ${response.status} ${payload}`);
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
