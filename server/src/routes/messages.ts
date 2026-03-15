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
import { sendTelegramMessage } from '../channels/telegram';

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
  const metadata = normalizeMetadata(payload.metadata);
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
  if (channelConfig) {
    const agentName = await fetchAgentName(c.env, agentId);
    try {
      const formattedBody = formatAgentMessage(agentName ?? 'agent', body);
      const delivered = await deliverToChannel(channelConfig.channel, channelConfig.config, formattedBody);
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
  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const { where, binds } = buildFilters(agentId, direction, status);
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
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to) VALUES (?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentId, 'boss_to_agent', 'async', parent.channel, body, 'sent', 'normal', parent.id)
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
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

function buildFilters(agentId: string, direction: Direction | null, status: Status | null) {
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
  return { where: clauses.join(' AND '), binds };
}

function clampNumber(value: string | null | undefined, fallback: number, maximum: number): number {
  const parsed = Number(value ?? fallback);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(parsed, maximum);
}

async function selectChannelConfig(env: Env, agentId: string, requested?: Channel) {
  const clauses = ['agent_id = ?', 'enabled = 1'];
  const binds: (string | number)[] = [agentId];
  if (requested) {
    clauses.push('channel = ?');
    binds.push(requested);
  }
  const row = await env.DB
    .prepare(`SELECT channel, config FROM channel_configs WHERE ${clauses.join(' AND ')} ORDER BY created_at DESC LIMIT 1`)
    .bind(...binds)
    .first<{ channel: Channel; config: string }>();
  if (!row) {
    throw new Error('no channel configured');
  }
  return { channel: row.channel, config: JSON.parse(row.config) as Record<string, unknown> };
}

async function deliverToChannel(channel: Channel, config: Record<string, unknown>, body: string): Promise<boolean> {
  if (channel === 'discord') {
    await sendDiscordMessage(requireDiscordConfig(config), body);
    return true;
  }
  if (channel === 'telegram') {
    await sendTelegramMessage(requireTelegramConfig(config), body);
    return true;
  }
  return false;
}

async function fetchMessageRow(env: Env, agentId: string, messageId: string) {
  return env.DB
    .prepare(
      'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE messages.id = ? AND messages.agent_id = ?'
    )
    .bind(messageId, agentId)
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
