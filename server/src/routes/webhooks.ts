// Webhook endpoints for Discord and Telegram to deliver boss messages.
// Exports POST handlers plus Telegram command registration for bot commands.
// Depends on Hono, auth middleware, channel adapters, and webhook helpers.

import { Context, Hono } from 'hono';
import { escapeHtml, sendTelegramMessage } from '../channels/telegram';
import { apiAuth, timingSafeEqual } from '../middleware/auth';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { findTelegramSessionRoute } from './session-channels';
import { requireTelegramConfig } from './delivery';
import {
  asString,
  evaluateRoutingRules,
  findEnabledChannelConfig,
  findMessageByIdempotencyKey,
  hasBossAccess,
  insertBossDiscordMessage,
  mapMessage,
  resolveBossForChannel,
} from './webhook-helpers';
import { handleTelegramCallbackQuery, handleTelegramReaction } from './telegram-webhook-actions';
import type { Env, MessageRow } from '../types';

const router = new Hono<{ Bindings: Env }>({});

router.post('/discord', async (c) => {
  const discordWebhookSecret = (c.env as Env & { DISCORD_WEBHOOK_SECRET?: string }).DISCORD_WEBHOOK_SECRET;
  const discordWebhookHeader = c.req.header('X-Webhook-Secret');
  if (!discordWebhookSecret) {
    return c.text('webhook secret not configured', 500);
  }
  if (!discordWebhookHeader || !timingSafeEqual(discordWebhookHeader, discordWebhookSecret)) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const message = payload['message'] as Record<string, unknown> | undefined;
  if (message && message['author'] && (message['author'] as Record<string, unknown>).bot) return c.text('ignored', 200);
  const channelId = asString(payload['channel_id']) ?? asString(message?.['channel_id']);
  const text =
    asString(message?.['content']) ??
    asString(payload['content']) ??
    asString((payload['data'] as Record<string, unknown> | undefined)?.['content']);
  if (!channelId || !text) return c.text('missing channel or body', 400);
  const idempotencyKey = asString(message?.['id']) ?? asString(payload['id']);
  const senderUserId = asString((message?.['author'] as Record<string, unknown>)?.['id']);
  const msgRef = message?.['message_reference'] as Record<string, unknown> | undefined;
  const replyToDiscordMsgId = asString(msgRef?.['message_id']);
  const inserted = await insertBossDiscordMessage(c.env, channelId, text, senderUserId, replyToDiscordMsgId, idempotencyKey, payload);
  if (!inserted) return c.text('forbidden or failed', 403);
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, inserted.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'discord', 'message.send', 'message', inserted.id, 'discord'));
  return c.json(mapMessage(inserted), 201);
});

router.post('/telegram/register-commands', apiAuth, async (c) => {
  const payload = await c.req.json<{ bot_token?: string }>();
  if (!payload.bot_token) {
    return c.text('bot_token required', 400);
  }
  const response = await fetch(`https://api.telegram.org/bot${encodeURIComponent(payload.bot_token)}/setMyCommands`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      commands: [
        { command: 'msg', description: 'Send a message to the AI agent' },
        { command: 'status', description: 'Show agent session status' },
      ],
    }),
  });
  if (!response.ok) {
    return c.text(await response.text(), 502);
  }
  return c.json(await response.json(), 201);
});

router.post('/telegram', async (c) => {
  const telegramWebhookSecret = (c.env as Env & { TELEGRAM_WEBHOOK_SECRET?: string }).TELEGRAM_WEBHOOK_SECRET;
  const telegramWebhookHeader = c.req.header('X-Telegram-Bot-Api-Secret-Token');
  if (!telegramWebhookSecret) {
    return c.text('webhook secret not configured', 500);
  }
  if (!telegramWebhookHeader || !timingSafeEqual(telegramWebhookHeader, telegramWebhookSecret)) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const callbackQuery = payload['callback_query'] as Record<string, unknown> | undefined;
  if (callbackQuery) return handleTelegramCallbackQuery(c, callbackQuery);
  const reaction = payload['message_reaction'] as Record<string, unknown> | undefined;
  if (reaction) return handleTelegramReaction(c, reaction);
  return handleTelegramMessage(c, payload);
});

export const webhooksRouter = router;

type TelegramCommand = { body: string | null; name: 'msg' | 'status' };
type TelegramConfigRow = { agent_id: string; config: string };
type TelegramWebhookContext = Context<{ Bindings: Env }>;

async function handleTelegramMessage(c: TelegramWebhookContext, payload: Record<string, unknown>): Promise<Response> {
  const message = payload['message'] as Record<string, unknown> | undefined;
  if (message && message['from'] && (message['from'] as Record<string, unknown>).is_bot) return c.text('ignored', 200);
  const chatId = asString((message?.['chat'] as Record<string, unknown> | undefined)?.['id']);
  const text = asString(message?.['text']);
  const threadId = typeof message?.['message_thread_id'] === 'number' ? message['message_thread_id'] : undefined;
  if (!chatId || !text) return c.text('missing chat or body', 400);
  if (!(await findEnabledChannelConfig(c.env, 'telegram', chatId))) return c.text('forbidden', 403);

  const target = await findTelegramTarget(c.env, chatId, threadId);
  if (!target) return c.text('forbidden', 403);
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(
    c.env,
    'telegram',
    asString((message?.['from'] as Record<string, unknown>)?.['id']),
    false,
  );
  if (bossError) return c.text(bossError, 403);
  if (bossInfo && !(await hasBossAccess(c.env, bossInfo.id, target.configRow.agent_id, bossInfo.role))) {
    return c.text('no access to this agent', 403);
  }

  const command = extractTelegramCommand(message, text);
  if (command?.name === 'status') return handleTelegramStatusCommand(c, target.configRow, threadId);
  const body = command?.name === 'msg' ? command.body : text;
  if (!body) return c.text('missing chat or body', 400);
  return createTelegramBossMessage(c, payload, message, body, target, bossInfo);
}

async function createTelegramBossMessage(
  c: TelegramWebhookContext,
  payload: Record<string, unknown>,
  message: Record<string, unknown> | undefined,
  body: string,
  target: { configRow: TelegramConfigRow; targetSessionId: string | null },
  bossInfo: { id: string; name: string; role: string } | null,
): Promise<Response> {
  const idempotencyKey = asString(payload['update_id']);
  if (idempotencyKey) {
    const existing = await findMessageByIdempotencyKey(c.env, target.configRow.agent_id, idempotencyKey);
    if (existing) return c.json(mapMessage(existing), 200);
  }
  const routedAgentId = target.targetSessionId ? null : await evaluateRoutingRules(c.env, 'telegram', body, target.configRow.agent_id);
  const agentId = routedAgentId ?? target.configRow.agent_id;
  const replyTo = await resolveTelegramReplyTo(c.env, agentId, message);
  const metadata = bossInfo ? { ...payload, boss_id: bossInfo.id, boss_name: bossInfo.name, source: 'telegram' } : { ...payload, source: 'telegram' };
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, idempotency_key, metadata, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
    )
    .bind(agentId, 'boss_to_agent', 'async', 'telegram', body, 'sent', 'normal', replyTo, idempotencyKey ?? null, JSON.stringify(metadata), target.targetSessionId)
    .first<MessageRow>();
  if (!inserted) return c.text('failed to persist', 500);
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, agentId, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, bossInfo ? 'boss' : 'system', bossInfo?.id ?? 'telegram', 'message.send', 'message', inserted.id, 'telegram'));
  return c.json(mapMessage(inserted), 201);
}

async function findTelegramTarget(env: Env, chatId: string, threadId: number | undefined): Promise<{ configRow: TelegramConfigRow; targetSessionId: string | null } | null> {
  if (threadId) {
    const sessionRoute = await findTelegramSessionRoute(env, chatId, threadId);
    if (sessionRoute) {
      return { configRow: { agent_id: sessionRoute.agent_id, config: sessionRoute.config }, targetSessionId: sessionRoute.session_id };
    }
    const threaded = await env.DB
      .prepare(
        "SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND enabled = 1 AND json_extract(config, '$.chat_id') = ? AND json_extract(config, '$.message_thread_id') = ?",
      )
      .bind(chatId, threadId)
      .first<TelegramConfigRow>();
    if (threaded) return { configRow: threaded, targetSessionId: null };
    return null;
  }
  const unthreaded = await env.DB
    .prepare(
      "SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND enabled = 1 AND json_extract(config, '$.chat_id') = ? AND json_extract(config, '$.message_thread_id') IS NULL",
    )
    .bind(chatId)
    .first<TelegramConfigRow>();
  if (unthreaded) return { configRow: unthreaded, targetSessionId: null };
  const fallback = await env.DB
    .prepare("SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND enabled = 1 AND json_extract(config, '$.chat_id') = ?")
    .bind(chatId)
    .first<TelegramConfigRow>();
  return fallback ? { configRow: fallback, targetSessionId: null } : null;
}

async function resolveTelegramReplyTo(env: Env, agentId: string, message: Record<string, unknown> | undefined): Promise<string | null> {
  const replyToTgId = (message?.['reply_to_message'] as Record<string, unknown> | undefined)?.['message_id'] as number | undefined;
  if (replyToTgId) {
    const parent = await env.DB
      .prepare("SELECT id FROM messages WHERE agent_id = ? AND channel = 'telegram' AND json_extract(metadata, '$.telegram_message_id') = ? LIMIT 1")
      .bind(agentId, replyToTgId)
      .first<{ id: string }>();
    return parent?.id ?? null;
  }
  const pending = await env.DB
    .prepare(
      "SELECT id FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND mode = 'blocking' AND channel = 'telegram' AND status IN ('sent', 'delivered') ORDER BY created_at DESC LIMIT 1",
    )
    .bind(agentId)
    .first<{ id: string }>();
  return pending?.id ?? null;
}

function extractTelegramCommand(message: Record<string, unknown> | undefined, text: string): TelegramCommand | null {
  const entities = Array.isArray(message?.['entities']) ? (message?.['entities'] as Record<string, unknown>[]) : [];
  const entity = entities.find((value) => value['type'] === 'bot_command' && value['offset'] === 0);
  const length = typeof entity?.['length'] === 'number' ? entity['length'] : 0;
  if (length < 2) return null;
  const commandText = text.slice(0, length);
  const commandName = commandText.slice(1).split('@')[0];
  if (commandName !== 'msg' && commandName !== 'status') return null;
  return { name: commandName, body: text.slice(length).trimStart() || null };
}

async function handleTelegramStatusCommand(c: TelegramWebhookContext, configRow: TelegramConfigRow, threadId: number | undefined): Promise<Response> {
  const sessions = await c.env.DB
    .prepare("SELECT * FROM sessions WHERE agent_id = ? AND last_seen_at > datetime('now', '-15 minutes') ORDER BY last_seen_at DESC")
    .bind(configRow.agent_id)
    .all<{ label: string | null; status: string; status_text: string | null }>();
  const agent = await c.env.DB.prepare('SELECT name FROM api_keys WHERE id = ?').bind(configRow.agent_id).first<{ name: string }>();
  const config = requireTelegramConfig(JSON.parse(configRow.config) as Record<string, unknown>);
  await sendTelegramMessage(config, formatTelegramStatusMessage(agent?.name ?? configRow.agent_id, sessions.results ?? []), {
    messageThreadId: threadId,
  });
  return c.json({ ok: true }, 200);
}

function formatTelegramStatusMessage(agentName: string, sessions: { label: string | null; status: string; status_text: string | null }[]): string {
  if (!sessions.length) {
    return `<b>${escapeHtml(agentName)}</b>\nNo active sessions in the last 15 minutes.`;
  }
  const lines = sessions.map((session) => {
    const label = escapeHtml(session.label ?? 'unnamed');
    const status = escapeHtml(session.status);
    const details = session.status_text ? ` (${escapeHtml(session.status_text)})` : '';
    return `• ${label}: ${status}${details}`;
  });
  return `<b>${escapeHtml(agentName)}</b>\n${sessions.length} active session(s)\n${lines.join('\n')}`;
}
