// Webhook endpoints for Discord and Telegram to deliver boss messages.
// Exports POST handlers that insert boss_to_agent rows and return the message.
// Depends on Hono, the D1 binding, and shared message typings.

import { Hono, Context } from 'hono';
import type { Env, MessageResponse, MessageRow } from '../types';
import { sendTelegramTyping, answerCallbackQuery, editMessageReplyMarkup } from '../channels/telegram';
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
  // Check routing rules: if a rule matches, override the target agent
  const routedAgentId = await evaluateRoutingRules(c.env, 'discord', text, agentRow.agent_id);
  if (routedAgentId) {
    agentRow.agent_id = routedAgentId;
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
  // Check routing rules: if a rule matches, override the target agent
  const routedAgentId = await evaluateRoutingRules(c.env, 'telegram', text, configRow.agent_id);
  if (routedAgentId) {
    configRow.agent_id = routedAgentId;
  }
  // Detect Telegram reply-to and link to original hiboss message
  const replyToMessage = message?.['reply_to_message'] as Record<string, unknown> | undefined;
  const replyToTgId = replyToMessage?.['message_id'] as number | undefined;
  let replyTo: string | null = null;
  if (replyToTgId) {
    const parent = await c.env.DB
      .prepare(
        "SELECT id FROM messages WHERE agent_id = ? AND channel = 'telegram' AND json_extract(metadata, '$.telegram_message_id') = ? LIMIT 1"
      )
      .bind(configRow.agent_id, replyToTgId)
      .first<{ id: string }>();
    if (parent) {
      replyTo = parent.id;
    }
  }
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(configRow.agent_id, 'boss_to_agent', 'async', 'telegram', text, 'sent', 'normal', replyTo, JSON.stringify(payload))
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, configRow.agent_id, inserted));
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
  // Find the original message by prefix (with metadata for actions)
  const parentMsg = await c.env.DB
    .prepare('SELECT id, metadata FROM messages WHERE id LIKE ? AND agent_id = ? LIMIT 1')
    .bind(`${msgPrefix}%`, configRow.agent_id)
    .first<{ id: string; metadata: string | null }>();
  if (!parentMsg) {
    return c.text('message not found', 404);
  }
  // If parent has actions in metadata, copy the matched action to reply metadata
  let replyMetadata: string | null = null;
  if (parentMsg.metadata) {
    try {
      const parentMeta = JSON.parse(parentMsg.metadata) as Record<string, unknown>;
      const actions = parentMeta['actions'] as Record<string, string> | undefined;
      if (actions && typeof actions === 'object' && actions[selectedOption]) {
        replyMetadata = JSON.stringify({ action: actions[selectedOption] });
      }
    } catch { /* ignore parse errors */ }
  }
  // Insert the button press as a boss reply
  const inserted = await c.env.DB
    .prepare('INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *')
    .bind(configRow.agent_id, 'boss_to_agent', 'async', 'telegram', selectedOption, 'sent', 'normal', parentMsg.id, replyMetadata)
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

async function evaluateRoutingRules(env: Env, channel: string, body: string, defaultAgentId: string): Promise<string | null> {
  const rules = await env.DB
    .prepare('SELECT target_agent_id, pattern FROM routing_rules WHERE channel = ? AND enabled = 1 ORDER BY priority DESC')
    .bind(channel)
    .all<{ target_agent_id: string; pattern: string }>();
  for (const rule of rules.results ?? []) {
    try {
      if (new RegExp(rule.pattern).test(body)) {
        return rule.target_agent_id !== defaultAgentId ? rule.target_agent_id : null;
      }
    } catch {
      // Skip invalid regex patterns
    }
  }
  return null;
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
