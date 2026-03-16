// Helper functions for message route handlers: delivery, formatting, DB queries.
// Exports utility functions used by the messages router.
// Depends on types, channel adapters, and D1 bindings.

import type {
  Channel,
  DiscordChannelConfig,
  Direction,
  Env,
  MessageResponse,
  MessageRow,
  Metadata,
  Priority,
  Status,
  TelegramChannelConfig,
} from '../types';
import { sendDiscordMessage } from '../channels/discord';
import {
  escapeHtml,
  formatTelegramAgentMessage,
  isImageUrl,
  sendTelegramDocument,
  sendTelegramMessage,
  sendTelegramPhoto,
} from '../channels/telegram';

const channelOptions: Channel[] = ['discord', 'telegram', 'email'];
export const priorityOptions: Priority[] = ['critical', 'high', 'normal', 'low'];

export function mapMessageRow(row: MessageRow): MessageResponse {
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

export function normalizeMetadata(value: unknown): Metadata {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

export function validateOption<T extends string>(value: unknown, options: readonly T[], fallback?: T): T | null {
  if (typeof value === 'string' && options.includes(value as T)) {
    return value as T;
  }
  if (fallback) {
    return fallback;
  }
  return null;
}

export function validateChannel(value: unknown): Channel | undefined {
  if (typeof value === 'string' && channelOptions.includes(value as Channel)) {
    return value as Channel;
  }
  return undefined;
}

export function buildFilters(agentId: string, direction: Direction | null, status: Status | null, priority?: Priority[], type?: string) {
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
  if (type) {
    clauses.push('type = ?');
    binds.push(type);
  }
  return { where: clauses.join(' AND '), binds };
}

export function parsePriorityFilter(value: string | undefined): Priority[] | undefined {
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

export function clampNumber(value: string | null | undefined, fallback: number, maximum: number): number {
  const parsed = Number(value ?? fallback);
  if (Number.isNaN(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.min(parsed, maximum);
}

export async function selectChannelConfig(env: Env, agentId: string, requested?: Channel) {
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

export async function fetchAllChannelConfigs(env: Env, agentId: string) {
  const rows = await env.DB
    .prepare('SELECT channel, config FROM channel_configs WHERE agent_id = ? AND enabled = 1')
    .bind(agentId)
    .all<{ channel: Channel; config: string }>();
  return (rows.results ?? []).map((r) => ({
    channel: r.channel,
    config: JSON.parse(r.config) as Record<string, unknown>,
  }));
}

export async function deliverReply(
  channel: Channel,
  config: Record<string, unknown>,
  agentName: string,
  body: string,
  replyToTelegramId?: number,
): Promise<DeliveryResult> {
  if (channel === 'discord') {
    await sendDiscordMessage(requireDiscordConfig(config), formatAgentMessage(agentName, body));
    return { delivered: true };
  }
  if (channel === 'telegram') {
    const tgBody = formatTelegramAgentMessage(agentName, body);
    const telegramMessageId = await sendTelegramMessage(requireTelegramConfig(config), tgBody, { replyToMessageId: replyToTelegramId });
    return { delivered: true, telegramMessageId };
  }
  return { delivered: false };
}

export async function fetchMessageRow(env: Env, agentId: string, messageId: string) {
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

export async function fetchReplies(env: Env, parentId: string) {
  const result = await env.DB
    .prepare(
      'SELECT messages.*, api_keys.name AS agent_name FROM messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id WHERE reply_to = ? ORDER BY messages.created_at ASC'
    )
    .bind(parentId)
    .all<MessageRow>();
  return (result.results ?? []).map(mapMessageRow);
}

export async function fetchMessageWithReplies(env: Env, agentId: string, messageId: string) {
  const row = await fetchMessageRow(env, agentId, messageId);
  if (!row) {
    return null;
  }
  const replyList = await fetchReplies(env, row.id);
  return { ...mapMessageRow(row), replies: replyList };
}

export function formatAgentMessage(name: string, body: string): string {
  return `[${name}] ${body}`;
}

export async function fetchAgentName(env: Env, agentId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ name: string }>();
  return row?.name ?? null;
}

export function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function requireDiscordConfig(config: Record<string, unknown>): DiscordChannelConfig {
  const channelId = config['channel_id'];
  const token = config['bot_token'];
  if (typeof channelId !== 'string' || typeof token !== 'string') {
    throw new Error('discord config malformed');
  }
  return { channel_id: channelId, bot_token: token };
}

export function requireTelegramConfig(config: Record<string, unknown>): TelegramChannelConfig {
  const chatId = config['chat_id'];
  const token = config['bot_token'];
  if (typeof chatId !== 'string' || typeof token !== 'string') {
    throw new Error('telegram config malformed');
  }
  return { chat_id: chatId, bot_token: token };
}

export function parseOptions(value: unknown): string[] | undefined {
  if (Array.isArray(value) && value.every((v) => typeof v === 'string')) {
    return value.length > 0 ? (value as string[]) : undefined;
  }
  if (typeof value === 'string' && value.trim()) {
    return value.split(',').map((s) => s.trim()).filter(Boolean);
  }
  return undefined;
}

export function buildInlineKeyboard(messageId: string, options: string[]): { text: string; callback_data: string }[][] {
  return options.map((opt) => [{ text: opt, callback_data: `${messageId.slice(0, 8)}:${opt}` }]);
}

export type DeliveryResult = { delivered: false } | { delivered: true; telegramMessageId?: number };

export async function deliverToChannelWithOptions(
  channel: Channel,
  config: Record<string, unknown>,
  agentName: string,
  body: string,
  inlineKeyboard?: { text: string; callback_data: string }[][],
  fileUrl?: string,
): Promise<DeliveryResult> {
  if (channel === 'discord') {
    const discordBody = formatAgentMessage(agentName, body);
    await sendDiscordMessage(requireDiscordConfig(config), fileUrl ? `${discordBody}\n${fileUrl}` : discordBody);
    return { delivered: true };
  }
  if (channel === 'telegram') {
    const tgConfig = requireTelegramConfig(config);
    const tgBody = formatTelegramAgentMessage(agentName, body);
    let telegramMessageId: number | undefined;
    if (fileUrl) {
      const caption = escapeHtml(`[${agentName}] ${body}`);
      if (isImageUrl(fileUrl)) {
        telegramMessageId = await sendTelegramPhoto(tgConfig, fileUrl, caption);
      } else {
        telegramMessageId = await sendTelegramDocument(tgConfig, fileUrl, caption);
      }
    } else {
      telegramMessageId = await sendTelegramMessage(tgConfig, tgBody, { inlineKeyboard });
    }
    return { delivered: true, telegramMessageId };
  }
  return { delivered: false };
}

export function extractTelegramMessageId(metadata: string | null): number | undefined {
  const meta = safeParse(metadata);
  if (!meta || typeof meta !== 'object') return undefined;
  const record = meta as Record<string, unknown>;
  // Flat key: set by delivery handler (agent_to_boss messages)
  const flat = record['telegram_message_id'];
  if (typeof flat === 'number') return flat;
  // Nested key: raw Telegram payload stored by webhook (boss_to_agent messages)
  const msg = record['message'];
  if (msg && typeof msg === 'object') {
    const id = (msg as Record<string, unknown>)['message_id'];
    if (typeof id === 'number') return id;
  }
  return undefined;
}
