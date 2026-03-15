// Webhook endpoints for Discord and Telegram to deliver boss messages.
// Exports POST handlers that insert boss_to_agent rows and return the message.
// Depends on Hono, the D1 binding, and shared message typings.

import { Hono } from 'hono';
import type { Env, MessageResponse, MessageRow } from '../types';

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
  return c.json(mapMessage(inserted), 201);
});

router.post('/telegram', async (c) => {
  const payload = await c.req.json<Record<string, unknown>>();
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
  const agentRow = await c.env.DB
    .prepare(
      "SELECT agent_id FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ?"
    )
    .bind(chatId)
    .first<{ agent_id: string }>();
  if (!agentRow) {
    return c.text('no agent for chat', 404);
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
  return c.json(mapMessage(inserted), 201);
});

export const webhooksRouter = router;

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
