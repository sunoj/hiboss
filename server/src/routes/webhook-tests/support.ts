// Synthetic channel configuration, positive update fixtures and request helpers.
// Exports shared webhook setup and case registration; malformed updates stay inline.

import { env } from 'cloudflare:test';
import { it } from 'vitest';
import type { MessageResponse } from '../../types';
import { testRequest, testJson } from '../../test-request';
import { seedDatabase, getTestAgentId } from '../../test-helpers';

export const TELEGRAM_SECRET = 'test-telegram-secret';
export const DISCORD_SECRET = 'test-discord-secret';

export async function seedWebhooks(): Promise<void> {
  await seedDatabase();
  env.TELEGRAM_WEBHOOK_SECRET = TELEGRAM_SECRET;
  env.DISCORD_WEBHOOK_SECRET = DISCORD_SECRET;
  const agentId = getTestAgentId();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(agentId, 'telegram', '{"chat_id":"test-chat","bot_token":"fake-token"}')
    .run();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(agentId, 'discord', '{"channel_id":"test-discord-ch","bot_token":"fake-token"}')
    .run();
}

export async function postTelegramWebhook(payload: Record<string, unknown>): Promise<Response> {
  return testRequest('POST', 'https://test.local/api/webhooks/telegram', {
    'Content-Type': 'application/json',
    'X-Telegram-Bot-Api-Secret-Token': TELEGRAM_SECRET,
  }, payload);
}

export async function postDiscordWebhook(payload: Record<string, unknown>): Promise<Response> {
  return testRequest('POST', 'https://test.local/api/webhooks/discord', {
    'Content-Type': 'application/json',
    'X-Webhook-Secret': DISCORD_SECRET,
  }, payload);
}

export function telegramCase(name: string, run: () => void | Promise<void>): void {
  it(`POST /api/webhooks/telegram ${name}`, run);
}

export function discordCase(name: string, run: () => void | Promise<void>): void {
  it(`POST /api/webhooks/discord ${name}`, run);
}

export function telegramText(
  text: string, messageId?: number, reply?: { message_id: number },
): Record<string, unknown> {
  return { message: {
    ...(messageId === undefined ? {} : { message_id: messageId }),
    chat: { id: 'test-chat', type: 'private' },
    text,
    from: { id: 1, is_bot: false },
    ...(reply === undefined ? {} : { reply_to_message: reply }),
  } };
}

export function telegramCallback(
  id: string, data: string, messageId: number, text: string,
): Record<string, unknown> {
  return { callback_query: { id, data, message: {
    message_id: messageId,
    chat: { id: 'test-chat', type: 'private' },
    text,
  } } };
}

export async function createdTelegram(payload: Record<string, unknown>): Promise<MessageResponse> {
  return await testJson(201, postTelegramWebhook(payload)) as MessageResponse;
}

export async function createdDiscord(payload: Record<string, unknown>): Promise<MessageResponse> {
  return await testJson(201, postDiscordWebhook(payload)) as MessageResponse;
}
