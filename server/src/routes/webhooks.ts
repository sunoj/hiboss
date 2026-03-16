// Webhook endpoints for Discord and Telegram to deliver boss messages.
// Exports POST handlers that insert boss_to_agent rows and return the message.
// Depends on Hono, the D1 binding, and shared message typings.

import { Hono, Context } from 'hono';
import type { Env, MessageResponse, MessageRow } from '../types';
import { sendTelegramTyping, setTelegramReaction, answerCallbackQuery, editMessageReplyMarkup } from '../channels/telegram';
import { notifyAgentCallback } from '../notify';

const router = new Hono<{ Bindings: Env }>({});

router.post('/discord', async (c) => {
  const payload = await c.req.json<Record<string, unknown>>();
  const message = payload['message'] as Record<string, unknown> | undefined;
  if (message && message['author'] && (message['author'] as Record<string, unknown>).bot) {
    return c.text('ignored', 200);
  }
  const interactionData = payload['data'] as Record<string, unknown> | undefined;
  const channelId = asString(payload['channel_id']) ?? asString(message?.['channel_id']);
  const text =
    asString(message?.['content']) ??
    asString(payload['content']) ??
    asString(interactionData?.['content']);
  if (!channelId || !text) {
    return c.text('missing channel or body', 400);
  }
  const agentRow = await c.env.DB
    .prepare(
      "SELECT agent_id FROM channel_configs WHERE channel = 'discord' AND json_extract(config, '$.channel_id') = ?"
    )
    .bind(channelId)
    .first<{ agent_id: string }>();
  if (!agentRow) {
    return c.text('no agent for channel', 404);
  }
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentRow.agent_id, 'boss_to_agent', 'async', 'discord', text, 'sent', 'normal', JSON.stringify(payload))
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, agentRow.agent_id, inserted));
  return c.json(mapMessage(inserted), 201);
});

router.post('/telegram', async (c) => {
  const payload = await c.req.json<Record<string, unknown>>();

  // Handle inline keyboard button press
  const callbackQuery = payload['callback_query'] as Record<string, unknown> | undefined;
  if (callbackQuery) {
    return handleCallbackQuery(c, callbackQuery);
  }

  const message = payload['message'] as Record<string, unknown> | undefined;
  if (message && message['from'] && (message['from'] as Record<string, unknown>).is_bot) {
    return c.text('ignored', 200);
  }
  const chat = message?.['chat'] as Record<string, unknown> | undefined;
  const chatId = asString(chat?.['id']);
  const text = asString(message?.['text']);
  if (!chatId || !text) {
    return c.text('missing chat or body', 400);
  }
  const configRow = await c.env.DB
    .prepare(
      "SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ?"
    )
    .bind(chatId)
    .first<{ agent_id: string; config: string }>();
  if (!configRow) {
    return c.text('no agent for chat', 404);
  }
  const agentRow = configRow;
  const telegramMessageId = message?.['message_id'] as number | undefined;
  let botToken: string | undefined;
  try {
    const parsed = JSON.parse(configRow.config) as Record<string, string>;
    botToken = parsed.bot_token;
  } catch {
    // config parse is best-effort
  }
  if (botToken && telegramMessageId) {
    c.executionCtx.waitUntil(setTelegramReaction(botToken, chatId, telegramMessageId, '👀'));
  }
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentRow.agent_id, 'boss_to_agent', 'async', 'telegram', text, 'sent', 'normal', JSON.stringify(payload))
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, agentRow.agent_id, inserted));
  return c.json(mapMessage(inserted), 201);
});

export const webhooksRouter = router;

async function handleCallbackQuery(c: Context<{ Bindings: Env }>, query: Record<string, unknown>): Promise<Response> {
  const data = asString(query['data']);
  const queryId = asString(query['id']);
  const chatMsg = query['message'] as Record<string, unknown> | undefined;
  const chat = chatMsg?.['chat'] as Record<string, unknown> | undefined;
  const chatId = asString(chat?.['id']);
  if (!data || !chatId) {
    return c.text('invalid callback', 400);
  }
  // data format: "msgIdPrefix:selectedOption"
  const colonIdx = data.indexOf(':');
  if (colonIdx < 1) {
    return c.text('invalid callback data', 400);
  }
  const msgPrefix = data.slice(0, colonIdx);
  const selectedOption = data.slice(colonIdx + 1);

  const configRow = await c.env.DB
    .prepare("SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ?")
    .bind(chatId)
    .first<{ agent_id: string; config: string }>();
  if (!configRow) {
    return c.text('no agent for chat', 404);
  }
  // Find the original message by prefix
  const parentMsg = await c.env.DB
    .prepare('SELECT id FROM messages WHERE id LIKE ? AND agent_id = ? LIMIT 1')
    .bind(`${msgPrefix}%`, configRow.agent_id)
    .first<{ id: string }>();
  if (!parentMsg) {
    return c.text('message not found', 404);
  }
  // Insert the button press as a boss reply
  const inserted = await c.env.DB
    .prepare('INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *')
    .bind(configRow.agent_id, 'boss_to_agent', 'async', 'telegram', selectedOption, 'sent', 'normal', parentMsg.id)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  // Acknowledge the button press and update message to show selection
  try {
    const parsed = JSON.parse(configRow.config) as Record<string, string>;
    if (parsed.bot_token && queryId) {
      c.executionCtx.waitUntil(answerCallbackQuery(parsed.bot_token, queryId, `Selected: ${selectedOption}`));
      const originalMsgId = chatMsg?.['message_id'] as number | undefined;
      const originalText = (chatMsg?.['text'] as string) ?? '';
      if (originalMsgId) {
        c.executionCtx.waitUntil(
          editMessageReplyMarkup(parsed.bot_token, chatId, originalMsgId, `${originalText}\n\n✅ Selected: ${selectedOption}`)
        );
      }
    }
  } catch {
    // best-effort
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, configRow.agent_id, inserted));
  return c.json(mapMessage(inserted), 201);
}

function asString(value: unknown): string | undefined {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return value.toString();
  }
  return undefined;
}

function mapMessage(row: MessageRow): MessageResponse {
  return {
    ...row,
    metadata: safeJson(row.metadata),
  };
}

function safeJson(value: string | null): Record<string, unknown> | null {
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as Record<string, unknown>;
  } catch {
    return null;
  }
}
