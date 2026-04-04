// Message edit propagation helpers for Discord and Telegram channel mirrors.
// Exports propagateMessageEdit() for PATCH /api/messages body updates.
// Depends on channel adapters, delivery formatters, and route query helpers.

import { editDiscordMessage } from '../channels/discord';
import { editTelegramMessageText, formatTelegramAgentMessage } from '../channels/telegram';
import type { Env, MessageRow } from '../types';
import { formatAgentMessage, requireDiscordConfig, requireTelegramConfig } from './delivery';
import { extractTelegramMessageId, fetchAgentName, selectChannelConfig } from './message-helpers';

export async function propagateMessageEdit(env: Env, message: MessageRow): Promise<void> {
  if (message.channel === 'discord') {
    await editDiscordMirror(env, message);
    return;
  }
  if (message.channel === 'telegram') {
    await editTelegramMirror(env, message);
  }
}

async function editDiscordMirror(env: Env, message: MessageRow): Promise<void> {
  const discordMessageId = extractDiscordMessageId(message.metadata);
  if (!discordMessageId) return;
  const channelConfig = await selectChannelConfig(env, message.agent_id, 'discord');
  const effectiveConfig = await resolveDiscordConfig(env, message, channelConfig.config);
  const discordConfig = requireDiscordConfig(effectiveConfig);
  const displayName = await fetchDisplayName(env, message);
  const content = discordConfig.webhook_url ? message.body : formatAgentMessage(displayName, message.body);
  await editDiscordMessage(discordConfig, discordMessageId, content);
}

async function editTelegramMirror(env: Env, message: MessageRow): Promise<void> {
  const telegramMessageId = extractTelegramMessageId(message.metadata);
  if (!telegramMessageId) return;
  const channelConfig = await selectChannelConfig(env, message.agent_id, 'telegram');
  const telegramConfig = requireTelegramConfig(channelConfig.config);
  const displayName = await fetchDisplayName(env, message);
  await editTelegramMessageText(telegramConfig, telegramMessageId, formatTelegramAgentMessage(displayName, message.body));
}

async function fetchDisplayName(env: Env, message: MessageRow): Promise<string> {
  const agentName = await fetchAgentName(env, message.agent_id) ?? 'agent';
  if (!message.session_id) return agentName;
  const session = await env.DB
    .prepare('SELECT label FROM sessions WHERE id = ?')
    .bind(message.session_id)
    .first<{ label: string | null }>();
  return session?.label ? `${session.label} (${agentName})` : agentName;
}

async function resolveDiscordConfig(
  env: Env,
  message: MessageRow,
  config: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (!message.session_id || !config['use_threads']) return config;
  const session = await env.DB
    .prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(message.session_id)
    .first<{ discord_thread_id: string | null }>();
  if (!session?.discord_thread_id) return config;
  return {
    ...config,
    channel_id: session.discord_thread_id,
    thread_id: session.discord_thread_id,
  };
}

function extractDiscordMessageId(metadata: string | null): string | undefined {
  if (!metadata) return undefined;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    const nested = parsed['discord_msg'];
    if (typeof parsed['discord_message_id'] === 'string') return parsed['discord_message_id'];
    if (nested && typeof nested === 'object' && typeof (nested as Record<string, unknown>)['id'] === 'string') {
      return (nested as Record<string, unknown>)['id'] as string;
    }
  } catch {
    return undefined;
  }
  return undefined;
}
