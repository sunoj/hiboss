// Message edit propagation helpers for Discord and Telegram channel mirrors.
// Exports propagateMessageEdit() for PATCH /api/messages body updates.
// Depends on channel adapters, delivery formatters, and route query helpers.

import { fetchAgentName, fetchSessionLabel, resolveDiscordConfig } from '../message-context';
import { editDiscordMessage } from '../channels/discord';
import {
  editTelegramCaption,
  editTelegramMessageText,
  formatTelegramAgentMessage,
  formatTelegramAttachmentCaption,
} from '../channels/telegram';
import type { Env, MessageRow } from '../types';
import { formatAgentMessage, requireDiscordConfig, requireTelegramConfig } from './delivery';
import { extractTelegramMessageId, selectChannelConfig } from './message-helpers';

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
  if (messageHasOptions(message.metadata)) {
    await editTelegramMessageText(telegramConfig, telegramMessageId, formatTelegramAgentMessage(displayName, message.body));
    return;
  }
  if (messageHasFileUrl(message.metadata)) {
    await editTelegramCaption(telegramConfig, telegramMessageId, formatTelegramAttachmentCaption(displayName, message.body));
    return;
  }
  await editTelegramMessageText(telegramConfig, telegramMessageId, formatTelegramAgentMessage(displayName, message.body));
}

async function fetchDisplayName(env: Env, message: MessageRow): Promise<string> {
  const agentName = await fetchAgentName(env, message.agent_id) ?? 'agent';
  if (!message.session_id) return agentName;
  const sessionLabel = await fetchSessionLabel(env, message.session_id);
  return sessionLabel ? `${sessionLabel} (${agentName})` : agentName;
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

function messageHasFileUrl(metadata: string | null): boolean {
  if (!metadata) return false;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    return typeof parsed['file_url'] === 'string' && parsed['file_url'].trim().length > 0;
  } catch {
    return false;
  }
}

function messageHasOptions(metadata: string | null): boolean {
  if (!metadata) return false;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    return Array.isArray(parsed['options']) && parsed['options'].length > 0;
  } catch {
    return false;
  }
}
