// Router that implements agent-facing messaging endpoints atop the D1 schema.
// Exports POST/GET/PATCH/poll handlers for /api/messages and mounts helpers.
// Depends on Hono, the auth middleware, channel adapters, and shared types.

import { Hono } from 'hono';
import type {
  Channel,
  DiscordChannelConfig,
  Direction,
  Env,
  MessageResponse,
  MessageRow,
  Metadata,
  Mode,
  Priority,
  Status,
  TelegramChannelConfig,
} from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { sendDiscordMessage } from '../channels/discord';
import { sendTelegramMessage, sendTelegramPhoto, sendTelegramDocument, isImageUrl, setTelegramReaction, formatTelegramAgentMessage, escapeMarkdownV2 } from '../channels/telegram';

const MAX_LIMIT = 100;
const DEFAULT_TIMEOUT_SECONDS = 300;
const WAIT_INTERVAL_MS = 1000;
const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

const modeOptions: Mode[] = ['async', 'blocking'];
const priorityOptions: Priority[] = ['critical', 'high', 'normal', 'low'];
const channelOptions: Channel[] = ['discord', 'telegram', 'email'];

routes.post('/', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const mode = validateOption<Mode>(payload.mode, modeOptions, 'async');
  const priority = validateOption<Priority>(payload.priority, priorityOptions, 'normal');
  const requestedChannel = validateChannel(payload.channel);
  const fileUrl = typeof payload.file_url === 'string' ? payload.file_url.trim() : undefined;
  const rawMetadata = normalizeMetadata(payload.metadata) ?? {};
  if (fileUrl) (rawMetadata as Record<string, unknown>)['file_url'] = fileUrl;
  const metadata = Object.keys(rawMetadata as Record<string, unknown>).length > 0 ? rawMetadata : null;
  let channelConfig: { channel: Channel; config: Record<string, unknown> } | null = null;
  try {
    channelConfig = await selectChannelConfig(c.env, agentId, requestedChannel);
  } catch {
    // No channel configured — message will be stored without delivery.
  }
  const channel = channelConfig?.channel ?? requestedChannel ?? null;
  const metadataJson = metadata ? JSON.stringify(metadata) : null;
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentId, 'agent_to_boss', mode, channel, body, 'sent', priority, metadataJson)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  const options = parseOptions(payload.options);
  if (channelConfig) {
    const agentName = await fetchAgentName(c.env, agentId);
    try {
      const name = agentName ?? 'agent';
      const inlineKeyboard = options ? buildInlineKeyboard(inserted.id, options) : undefined;
      const delivered = await deliverToChannelWithOptions(channelConfig.channel, channelConfig.config, name, body, inlineKeyboard, fileUrl);
      if (delivered) {
        await c.env.DB
          .prepare("UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ?")
          .bind(inserted.id)
          .run();
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'delivery failure';
      return c.json({ error: message, id: inserted.id, status: inserted.status }, 502);
    }
  }
  return c.json({ id: inserted.id, status: inserted.status, created_at: inserted.created_at }, 201);
});

routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const unread = c.req.query('unread');
  const directionParam = unread === 'true' ? 'boss_to_agent' : c.req.query('direction');
  const statusParam = unread === 'true' ? 'sent' : c.req.query('status');
  const direction = validateOption<Direction>(directionParam, ['agent_to_boss', 'boss_to_agent']);
  const status = validateOption<Status>(statusParam, ['sent', 'delivered', 'read', 'replied']);
  const priorityFilter = parsePriorityFilter(c.req.query('priority'));
  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const { where, binds } = buildFilters(agentId, direction, status, priorityFilter);
  const rows = await c.env.DB
    .prepare(
      `SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE ${where} ORDER BY messages.created_at DESC LIMIT ? OFFSET ?`
    )
    .bind(...binds, limit, offset)
    .all<MessageRow>();
  const countRow = await c.env.DB
    .prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`)
    .bind(...binds)
    .first<{ total: number }>();
  return c.json({ messages: (rows.results ?? []).map(mapMessageRow), total: countRow?.total ?? 0 });
});

routes.get('/:id', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageWithReplies(c.env, agentId, c.req.param('id'));
  if (!message) {
    return c.text('not found', 404);
  }
  return c.json(message);
});

routes.post('/:id/reply', async (c) => {
  const agentId = getAgentId(c);
  const parent = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!parent) {
    return c.text('not found', 404);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  const replyDirection: Direction = parent.direction === 'boss_to_agent' ? 'agent_to_boss' : 'boss_to_agent';
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentId, replyDirection, 'async', parent.channel, body, 'sent', 'normal', parent.id)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  if (replyDirection === 'agent_to_boss' && parent.channel) {
    try {
      const channelConfig = await selectChannelConfig(c.env, agentId, parent.channel as Channel);
      const agentName = await fetchAgentName(c.env, agentId);
      const name = agentName ?? 'agent';
      const telegramReplyId = extractTelegramMessageId(parent.metadata);
      const delivered = await deliverReply(channelConfig.channel, channelConfig.config, name, body, telegramReplyId);
      if (delivered) {
        await c.env.DB
          .prepare("UPDATE messages SET status = 'delivered', updated_at = datetime('now') WHERE id = ?")
          .bind(inserted.id)
          .run();
      }
      if (parent.channel === 'telegram') {
        c.executionCtx.waitUntil(markTelegramReplied(channelConfig.config, parent.metadata));
      }
    } catch {
      // Channel delivery failed — message is still stored.
    }
  }
  await c.env.DB
    .prepare("UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?")
    .bind(parent.id)
    .run();
  return c.json(mapMessageRow(inserted), 201);
});

routes.patch('/:id', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const status = validateOption<Status>(payload.status, ['sent', 'delivered', 'read', 'replied']);
  if (!status) {
    return c.text('status is required', 400);
  }
  const updated = await c.env.DB
    .prepare(
      'UPDATE messages SET status = ?, updated_at = datetime(\'now\') WHERE id = ? AND agent_id = ? RETURNING *'
    )
    .bind(status, c.req.param('id'), agentId)
    .first<MessageRow>();
  if (!updated) {
    return c.text('not found', 404);
  }
  if (status === 'read' && updated.direction === 'boss_to_agent' && updated.channel === 'telegram') {
    try {
      const channelConfig = await selectChannelConfig(c.env, agentId, 'telegram');
      const tgConfig = requireTelegramConfig(channelConfig.config);
      const telegramMsgId = extractTelegramMessageId(updated.metadata);
      if (telegramMsgId) {
        c.executionCtx.waitUntil(setTelegramReaction(tgConfig.bot_token, tgConfig.chat_id, telegramMsgId, '🔨'));
      }
    } catch {
      // Channel config not found — skip reaction silently.
    }
  }
  return c.json(mapMessageRow(updated));
});

routes.post('/:id/poll', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) {
    return c.text('not found', 404);
  }
  if (message.mode !== 'blocking') {
    return c.text('not blocking message', 400);
  }
  const timeoutSec = clampNumber(c.req.query('timeout'), DEFAULT_TIMEOUT_SECONDS, DEFAULT_TIMEOUT_SECONDS);
  const deadline = Date.now() + timeoutSec * 1000;
  while (true) {
    const current = await fetchMessageWithReplies(c.env, agentId, message.id);
    if (current && (current.replies?.length ?? 0) > 0) {
      return c.json(current);
    }
    if (Date.now() >= deadline) {
      const fallback = mapMessageRow(message);
      fallback.replies = [];
      return c.json(current ?? fallback);
    }
    await delay(Math.min(WAIT_INTERVAL_MS, deadline - Date.now()));
  }
});

export const messagesRouter = routes;

function mapMessageRow(row: MessageRow): MessageResponse {
  return {
    ...row,
    metadata: safeParse(row.metadata),
  };
}

function safeParse(value: string | null): Metadata {
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as Metadata;
  } catch {
    return null;
  }
}

function normalizeMetadata(value: unknown): Metadata {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function validateOption<T extends string>(value: unknown, options: readonly T[], fallback?: T): T | null {
  if (typeof value === 'string' && options.includes(value as T)) {
    return value as T;
  }
  if (fallback) {
    return fallback;
  }
  return null;
}

function validateChannel(value: unknown): Channel | undefined {
  if (typeof value === 'string' && channelOptions.includes(value as Channel)) {
    return value as Channel;
  }
  return undefined;
}

function buildFilters(agentId: string, direction: Direction | null, status: Status | null, priority?: Priority[]) {
  const clauses = ['agent_id = ?'];
  const binds: (string | number)[] = [agentId];
  if (direction) {
    clauses.push('direction = ?');
    binds.push(direction);
  }
  if (status) {
    clauses.push('status = ?');
    binds.push(status);
  }
  if (priority && priority.length > 0) {
    const placeholders = priority.map(() => '?').join(', ');
    clauses.push(`priority IN (${placeholders})`);
    binds.push(...priority);
  }
  return { where: clauses.join(' AND '), binds };
}

function parsePriorityFilter(value: string | undefined): Priority[] | undefined {
  if (!value) return undefined;
  const valid: Priority[] = [];
  for (const p of value.split(',')) {
    const trimmed = p.trim() as Priority;
    if (priorityOptions.includes(trimmed)) {
      valid.push(trimmed);
    }
  }
  return valid.length > 0 ? valid : undefined;
}

function clampNumber(value: string | null | undefined, fallback: number, maximum: number): number {
  const parsed = Number(value ?? fallback);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(parsed, maximum);
}

async function selectChannelConfig(env: Env, agentId: string, requested?: Channel) {
  if (requested) {
    const exact = await env.DB
      .prepare("SELECT channel, config FROM channel_configs WHERE agent_id = ? AND enabled = 1 AND channel = ? LIMIT 1")
      .bind(agentId, requested)
      .first<{ channel: Channel; config: string }>();
    if (exact) {
      return { channel: exact.channel, config: JSON.parse(exact.config) as Record<string, unknown> };
    }
  }
  const fallback = await env.DB
    .prepare("SELECT channel, config FROM channel_configs WHERE agent_id = ? AND enabled = 1 ORDER BY created_at DESC LIMIT 1")
    .bind(agentId)
    .first<{ channel: Channel; config: string }>();
  if (!fallback) {
    throw new Error('no channel configured');
  }
  return { channel: fallback.channel, config: JSON.parse(fallback.config) as Record<string, unknown> };
}

async function deliverReply(
  channel: Channel, config: Record<string, unknown>, agentName: string, body: string,
  replyToTelegramId?: number,
): Promise<boolean> {
  if (channel === 'discord') {
    await sendDiscordMessage(requireDiscordConfig(config), formatAgentMessage(agentName, body));
    return true;
  }
  if (channel === 'telegram') {
    const tgBody = formatTelegramAgentMessage(agentName, body);
    await sendTelegramMessage(requireTelegramConfig(config), tgBody, { replyToMessageId: replyToTelegramId });
    return true;
  }
  return false;
}

async function fetchMessageRow(env: Env, agentId: string, messageId: string) {
  const exact = await env.DB
    .prepare(
      'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id = ? AND messages.agent_id = ?'
    )
    .bind(messageId, agentId)
    .first<MessageRow>();
  if (exact) {
    return exact;
  }
  return env.DB
    .prepare(
      'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id LIKE ? AND messages.agent_id = ? LIMIT 1'
    )
    .bind(`${messageId}%`, agentId)
    .first<MessageRow>();
}

async function fetchReplies(env: Env, parentId: string) {
  const result = await env.DB
    .prepare(
      'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE reply_to = ? ORDER BY messages.created_at ASC'
    )
    .bind(parentId)
    .all<MessageRow>();
  return (result.results ?? []).map(mapMessageRow);
}

async function fetchMessageWithReplies(env: Env, agentId: string, messageId: string) {
  const row = await fetchMessageRow(env, agentId, messageId);
  if (!row) {
    return null;
  }
  const replyList = await fetchReplies(env, row.id);
  return { ...mapMessageRow(row), replies: replyList };
}

function formatAgentMessage(name: string, body: string): string {
  return `[${name}] ${body}`;
}

async function fetchAgentName(env: Env, agentId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ name: string }>();
  return row?.name ?? null;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function requireDiscordConfig(config: Record<string, unknown>): DiscordChannelConfig {
  const channelId = config['channel_id'];
  const token = config['bot_token'];
  if (typeof channelId !== 'string' || typeof token !== 'string') {
    throw new Error('discord config malformed');
  }
  return { channel_id: channelId, bot_token: token };
}

function requireTelegramConfig(config: Record<string, unknown>): TelegramChannelConfig {
  const chatId = config['chat_id'];
  const token = config['bot_token'];
  if (typeof chatId !== 'string' || typeof token !== 'string') {
    throw new Error('telegram config malformed');
  }
  return { chat_id: chatId, bot_token: token };
}

function parseOptions(value: unknown): string[] | undefined {
  if (Array.isArray(value) && value.every((v) => typeof v === 'string')) {
    return value.length > 0 ? value as string[] : undefined;
  }
  if (typeof value === 'string' && value.trim()) {
    return value.split(',').map((s) => s.trim()).filter(Boolean);
  }
  return undefined;
}

function buildInlineKeyboard(messageId: string, options: string[]): { text: string; callback_data: string }[][] {
  return options.map((opt) => [{ text: opt, callback_data: `${messageId.slice(0, 8)}:${opt}` }]);
}

async function deliverToChannelWithOptions(
  channel: Channel, config: Record<string, unknown>, agentName: string, body: string,
  inlineKeyboard?: { text: string; callback_data: string }[][],
  fileUrl?: string,
): Promise<boolean> {
  if (channel === 'discord') {
    const discordBody = formatAgentMessage(agentName, body);
    await sendDiscordMessage(requireDiscordConfig(config), fileUrl ? `${discordBody}\n${fileUrl}` : discordBody);
    return true;
  }
  if (channel === 'telegram') {
    const tgConfig = requireTelegramConfig(config);
    const tgBody = formatTelegramAgentMessage(agentName, body);
    if (fileUrl) {
      const caption = escapeMarkdownV2(`[${agentName}] ${body}`);
      if (isImageUrl(fileUrl)) {
        await sendTelegramPhoto(tgConfig, fileUrl, caption);
      } else {
        await sendTelegramDocument(tgConfig, fileUrl, caption);
      }
    } else {
      await sendTelegramMessage(tgConfig, tgBody, { inlineKeyboard });
    }
    return true;
  }
  return false;
}

function extractTelegramMessageId(metadata: string | null): number | undefined {
  const meta = safeParse(metadata) as Record<string, unknown> | null;
  const msg = meta?.['message'] as Record<string, unknown> | undefined;
  return msg?.['message_id'] as number | undefined;
}

async function markTelegramReplied(channelConfig: Record<string, unknown>, parentMetadata: string | null): Promise<void> {
  const tgConfig = requireTelegramConfig(channelConfig);
  const messageId = extractTelegramMessageId(parentMetadata);
  if (!messageId) return;
  await setTelegramReaction(tgConfig.bot_token, tgConfig.chat_id, messageId, '✅');
}
