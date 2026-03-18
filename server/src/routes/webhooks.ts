// Webhook endpoints for Discord and Telegram to deliver boss messages.
// Exports POST handlers that insert boss_to_agent rows and return the message.
// Depends on Hono, the D1 binding, and shared message typings.

import { Hono, Context } from 'hono';
import type { Env, MessageRow } from '../types';
import { sendTelegramTyping, answerCallbackQuery, editMessageReplyMarkup } from '../channels/telegram';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { asString, evaluateRoutingRules, hasBossAccess, mapMessage, resolveBossForChannel } from './webhook-helpers';

const router = new Hono<{ Bindings: Env }>({});

router.post('/discord', async (c) => {
  const discordWebhookSecret = (c.env as Env & { DISCORD_WEBHOOK_SECRET?: string }).DISCORD_WEBHOOK_SECRET;
  const discordWebhookHeader = c.req.header('X-Webhook-Secret');
  if (!discordWebhookSecret) {
    return c.text('webhook secret not configured', 500);
  }
  if (discordWebhookHeader !== discordWebhookSecret) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const message = payload['message'] as Record<string, unknown> | undefined;
  if (message && message['author'] && (message['author'] as Record<string, unknown>).bot) return c.text('ignored', 200);
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(
    c.env,
    'discord',
    asString((message?.['author'] as Record<string, unknown>)?.['id']),
    false
  );
  if (bossError) return c.text(bossError, 403);
  const interactionData = payload['data'] as Record<string, unknown> | undefined;
  const channelId = asString(payload['channel_id']) ?? asString(message?.['channel_id']);
  const text =
    asString(message?.['content']) ??
    asString(payload['content']) ??
    asString(interactionData?.['content']);
  if (!channelId || !text) return c.text('missing channel or body', 400);
  const agentRow = await c.env.DB
    .prepare(
      "SELECT agent_id FROM channel_configs WHERE channel = 'discord' AND json_extract(config, '$.channel_id') = ?"
    )
    .bind(channelId)
    .first<{ agent_id: string }>();
  if (!agentRow) return c.text('no agent for channel', 404);
  // Check routing rules: if a rule matches, override the target agent
  const routedAgentId = await evaluateRoutingRules(c.env, 'discord', text, agentRow.agent_id);
  if (routedAgentId) agentRow.agent_id = routedAgentId;
  if (bossInfo && !(await hasBossAccess(c.env, bossInfo.id, agentRow.agent_id, bossInfo.role))) return c.text('no access to this agent', 403);
  const discordMetadata = bossInfo ? { ...payload, boss_id: bossInfo.id, boss_name: bossInfo.name } : payload;
  // Auto-link to most recent pending blocking message for this agent
  let replyTo: string | null = null;
  const pending = await c.env.DB
    .prepare(
      "SELECT id FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND mode = 'blocking' AND channel = 'discord' AND status IN ('sent', 'delivered') ORDER BY created_at DESC LIMIT 1"
    )
    .bind(agentRow.agent_id)
    .first<{ id: string }>();
  if (pending) replyTo = pending.id;
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentRow.agent_id, 'boss_to_agent', 'async', 'discord', text, 'sent', 'normal', replyTo, JSON.stringify(discordMetadata))
    .first<MessageRow>();
  if (!inserted) return c.text('failed to persist', 500);
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, agentRow.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, bossInfo ? 'boss' : 'system', bossInfo?.id ?? 'discord', 'message.send', 'message', inserted.id, 'discord'));
  return c.json(mapMessage(inserted), 201);
});

router.post('/telegram', async (c) => {
  const telegramWebhookSecret = (c.env as Env & { TELEGRAM_WEBHOOK_SECRET?: string }).TELEGRAM_WEBHOOK_SECRET;
  const telegramWebhookHeader = c.req.header('X-Telegram-Bot-Api-Secret-Token');
  if (!telegramWebhookSecret) {
    return c.text('webhook secret not configured', 500);
  }
  if (telegramWebhookHeader !== telegramWebhookSecret) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();

  // Handle inline keyboard button press
  const callbackQuery = payload['callback_query'] as Record<string, unknown> | undefined;
  if (callbackQuery) return handleCallbackQuery(c, callbackQuery);

  // Handle boss reaction on a message
  const reaction = payload['message_reaction'] as Record<string, unknown> | undefined;
  if (reaction) return handleTelegramReaction(c, reaction);

  const message = payload['message'] as Record<string, unknown> | undefined;
  if (message && message['from'] && (message['from'] as Record<string, unknown>).is_bot) return c.text('ignored', 200);
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(
    c.env,
    'telegram',
    asString((message?.['from'] as Record<string, unknown>)?.['id']),
    false
  );
  if (bossError) return c.text(bossError, 403);
  const chat = message?.['chat'] as Record<string, unknown> | undefined;
  const chatId = asString(chat?.['id']);
  const text = asString(message?.['text']);
  const threadId = message?.['message_thread_id'] as number | undefined;
  if (!chatId || !text) return c.text('missing chat or body', 400);
  // Route by thread ID first (topics mode), then fall back to chat_id only
  let configRow: { agent_id: string; config: string } | null = null;
  if (threadId) {
    configRow = await c.env.DB
      .prepare(
        "SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ? AND json_extract(config, '$.message_thread_id') = ?"
      )
      .bind(chatId, threadId)
      .first<{ agent_id: string; config: string }>();
  }
  if (!configRow) {
    configRow = await c.env.DB
      .prepare(
        "SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ? AND json_extract(config, '$.message_thread_id') IS NULL"
      )
      .bind(chatId)
      .first<{ agent_id: string; config: string }>();
  }
  if (!configRow) {
    configRow = await c.env.DB
      .prepare(
        "SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ?"
      )
      .bind(chatId)
      .first<{ agent_id: string; config: string }>();
  }
  if (!configRow) return c.text('no agent for chat', 404);
  // Check routing rules: if a rule matches, override the target agent
  const routedAgentId = await evaluateRoutingRules(c.env, 'telegram', text, configRow.agent_id);
  if (routedAgentId) configRow.agent_id = routedAgentId;
  if (bossInfo && !(await hasBossAccess(c.env, bossInfo.id, configRow.agent_id, bossInfo.role))) return c.text('no access to this agent', 403);
  const telegramMetadata = bossInfo ? { ...payload, boss_id: bossInfo.id, boss_name: bossInfo.name } : payload;
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
    if (parent) replyTo = parent.id;
  }
  // Auto-link standalone messages (no explicit reply-to) to most recent pending blocking message
  if (!replyTo && !replyToTgId) {
    const pending = await c.env.DB
      .prepare(
        "SELECT id FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND mode = 'blocking' AND channel = 'telegram' AND status IN ('sent', 'delivered') ORDER BY created_at DESC LIMIT 1"
      )
      .bind(configRow.agent_id)
      .first<{ id: string }>();
    if (pending) replyTo = pending.id;
  }
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(configRow.agent_id, 'boss_to_agent', 'async', 'telegram', text, 'sent', 'normal', replyTo, JSON.stringify(telegramMetadata))
    .first<MessageRow>();
  if (!inserted) return c.text('failed to persist', 500);
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, configRow.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, bossInfo ? 'boss' : 'system', bossInfo?.id ?? 'telegram', 'message.send', 'message', inserted.id, 'telegram'));
  return c.json(mapMessage(inserted), 201);
});

export const webhooksRouter = router;

async function handleCallbackQuery(c: Context<{ Bindings: Env }>, query: Record<string, unknown>): Promise<Response> {
  const data = asString(query['data']);
  const queryId = asString(query['id']);
  const chatMsg = query['message'] as Record<string, unknown> | undefined;
  const chat = chatMsg?.['chat'] as Record<string, unknown> | undefined;
  const chatId = asString(chat?.['id']);
  if (!data || !chatId) return c.text('invalid callback', 400);
  // Look up config first — needed for answerCallbackQuery on all paths
  const configRow = await c.env.DB
    .prepare("SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ?")
    .bind(chatId)
    .first<{ agent_id: string; config: string }>();
  const botToken = configRow ? (JSON.parse(configRow.config) as Record<string, string>).bot_token : undefined;
  // Helper: always dismiss Telegram loading spinner, even on errors
  const answer = (text: string) => {
    if (botToken && queryId) c.executionCtx.waitUntil(answerCallbackQuery(botToken, queryId, text));
  };
  if (!configRow) { answer('Error'); return c.text('no agent for chat', 404); }
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(
    c.env, 'telegram', asString((query['from'] as Record<string, unknown>)?.['id']), true
  );
  if (bossError) { answer(bossError); return c.text(bossError, 403); }
  if (bossInfo && !(await hasBossAccess(c.env, bossInfo.id, configRow.agent_id, bossInfo.role))) {
    answer('No access'); return c.text('no access to this agent', 403);
  }
  // data format: "msgIdPrefix:selectedOption"
  const colonIdx = data.indexOf(':');
  if (colonIdx < 1) { answer('Invalid'); return c.text('invalid callback data', 400); }
  const msgPrefix = data.slice(0, colonIdx);
  const selectedOption = data.slice(colonIdx + 1);
  if (!/^[0-9a-f]{8,}$/i.test(msgPrefix)) { answer('Invalid'); return c.text('invalid message prefix', 400); }
  const parentMsg = await c.env.DB
    .prepare('SELECT id, metadata, status FROM messages WHERE id LIKE ? AND agent_id = ? LIMIT 1')
    .bind(`${msgPrefix}%`, configRow.agent_id)
    .first<{ id: string; metadata: string | null; status: string }>();
  if (!parentMsg) { answer('Not found'); return c.text('message not found', 404); }
  if (parentMsg.status === 'expired') { answer('Options expired'); return c.text('options expired', 410); }
  // If parent has actions in metadata, copy the matched action to reply metadata
  let replyMetadataRecord: Record<string, unknown> | null = null;
  if (parentMsg.metadata) {
    try {
      const parentMeta = JSON.parse(parentMsg.metadata) as Record<string, unknown>;
      const actions = parentMeta['actions'] as Record<string, string> | undefined;
      if (actions && typeof actions === 'object' && actions[selectedOption]) {
        replyMetadataRecord = { action: actions[selectedOption] };
      }
    } catch { /* ignore parse errors */ }
  }
  if (bossInfo) {
    replyMetadataRecord = { ...(replyMetadataRecord ?? {}), boss_id: bossInfo.id, boss_name: bossInfo.name };
  }
  const finalReplyMetadata = replyMetadataRecord ? JSON.stringify(replyMetadataRecord) : null;
  const inserted = await c.env.DB
    .prepare('INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *')
    .bind(configRow.agent_id, 'boss_to_agent', 'async', 'telegram', selectedOption, 'sent', 'normal', parentMsg.id, finalReplyMetadata)
    .first<MessageRow>();
  if (!inserted) { answer('Error'); return c.text('failed to persist', 500); }
  answer(`Selected: ${selectedOption}`);
  const originalMsgId = chatMsg?.['message_id'] as number | undefined;
  const originalText = (chatMsg?.['text'] as string) ?? '';
  if (botToken && originalMsgId) {
    c.executionCtx.waitUntil(
      editMessageReplyMarkup(botToken, chatId, originalMsgId, `${originalText}\n\n✅ Selected: ${selectedOption}`)
    );
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, configRow.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, bossInfo ? 'boss' : 'system', bossInfo?.id ?? 'telegram', 'message.callback', 'message', parentMsg.id, selectedOption));
  return c.json(mapMessage(inserted), 201);
}

async function handleTelegramReaction(c: Context<{ Bindings: Env }>, reaction: Record<string, unknown>): Promise<Response> {
  const chat = reaction['chat'] as Record<string, unknown> | undefined;
  const chatId = asString(chat?.['id']);
  const tgMsgId = reaction['message_id'] as number | undefined;
  if (!chatId || !tgMsgId) return c.text('invalid reaction', 400);
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(
    c.env,
    'telegram',
    asString((reaction['user'] as Record<string, unknown>)?.['id']),
    true
  );
  if (bossError) return c.text(bossError, 403);
  const configRow = await c.env.DB
    .prepare("SELECT agent_id FROM channel_configs WHERE channel = 'telegram' AND json_extract(config, '$.chat_id') = ?")
    .bind(chatId)
    .first<{ agent_id: string }>();
  if (!configRow) return c.text('no agent for chat', 404);
  if (bossInfo && !(await hasBossAccess(c.env, bossInfo.id, configRow.agent_id, bossInfo.role))) return c.text('no access to this agent', 403);
  // Find hiboss message by telegram_message_id
  const msg = await c.env.DB
    .prepare("SELECT id, metadata FROM messages WHERE agent_id = ? AND channel = 'telegram' AND json_extract(metadata, '$.telegram_message_id') = ? LIMIT 1")
    .bind(configRow.agent_id, tgMsgId)
    .first<{ id: string; metadata: string | null }>();
  if (!msg) return c.text('ok', 200); // Unknown message, ignore
  // Extract new reaction list
  const newReactions = reaction['new_reaction'] as { type: string; emoji?: string }[] | undefined;
  const emojis = (newReactions ?? []).filter((r) => r.type === 'emoji' && r.emoji).map((r) => r.emoji as string);
  const user = reaction['user'] as Record<string, unknown> | undefined;
  const userName = asString(user?.['first_name']) ?? asString(user?.['username']) ?? 'boss';
  // Update message metadata with reactions
  const meta = msg.metadata ? JSON.parse(msg.metadata) as Record<string, unknown> : {};
  meta['reactions'] = emojis.map((e) => ({ emoji: e, user: userName }));
  await c.env.DB.prepare('UPDATE messages SET metadata = ? WHERE id = ?').bind(JSON.stringify(meta), msg.id).run();
  return c.json({ ok: true });
}

// Boss auth, routing, and mapping helpers are in webhook-helpers.ts
