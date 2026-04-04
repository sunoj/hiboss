// Shared message forwarding helpers for agent and boss message routes.
// Exports channel validation plus delivery + persistence for forwarded messages.
// Depends on message queries/options, delivery helpers, and route-safe metadata parsing.

import type { Channel, Env, MessageRow } from '../types';
import { ensureThreadForSession, ensureTopicForAgent } from './message-options';
import { fetchAgentName, selectChannelConfig } from './message-queries';
import { ensureTopicForSession } from './session-channels';
import {
  deliverToChannelWithOptions,
  deliverWithRetry,
  requireTelegramConfig,
  safeParse,
} from './message-helpers';

const FORWARD_CHANNELS = ['discord', 'telegram'] as const;

export type ForwardChannel = (typeof FORWARD_CHANNELS)[number];

export function validateForwardChannel(value: unknown): ForwardChannel | null {
  if (value === 'discord' || value === 'telegram') return value;
  return null;
}

export function buildForwardBody(sourceChannel: Channel | null, body: string): string {
  return `[Forwarded from ${sourceChannel ?? 'unknown'}] ${body}`;
}

export async function forwardMessage(
  env: Env,
  original: MessageRow,
  targetChannel: ForwardChannel,
): Promise<MessageRow> {
  if (original.direction === 'boss_to_agent') {
    throw new Error('cannot forward boss messages');
  }
  const channelConfig = await selectChannelConfig(env, original.agent_id, targetChannel);
  if (channelConfig.channel !== targetChannel) {
    throw new Error('no channel configured');
  }
  const agentName = await fetchAgentName(env, original.agent_id) ?? 'agent';
  const avatar = await fetchForwardAvatar(env, original.agent_id);
  const sessionLabel = await fetchSessionLabel(env, original.session_id);
  const displayName = sessionLabel ? `${sessionLabel} (${agentName})` : agentName;
  const fileUrl = readForwardFileUrl(original.metadata);
  const forwardBody = buildForwardBody(original.channel, original.body);
  const metadata = buildForwardMetadata(original.channel, fileUrl);

  await ensureTopicForAgent(env, original.agent_id, channelConfig);
  await ensureForwardTelegramTopic(env, original.session_id, agentName, sessionLabel, channelConfig);

  const config = await resolveForwardConfig(env, original.session_id, channelConfig);
  const result = await deliverWithRetry(() =>
    deliverToChannelWithOptions(
      targetChannel,
      config,
      displayName,
      forwardBody,
      undefined,
      fileUrl,
      avatar,
      env,
      original.session_id,
    )
  );
  if (!result.delivered) throw new Error('forward delivery failed');

  const inserted = await env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, type, reply_to, metadata, session_id, target_agent_id, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(
      original.agent_id,
      original.direction,
      original.mode,
      targetChannel,
      forwardBody,
      'delivered',
      original.priority,
      'forwarded',
      original.id,
      JSON.stringify(mergeDeliveryMetadata(metadata, result)),
      original.session_id,
      original.target_agent_id,
      original.target_session_id,
    )
    .first<MessageRow>();
  if (!inserted) throw new Error('failed to persist');

  if (result.discordMessageId) {
    await ensureThreadForSession(env, original.agent_id, original.session_id, channelConfig, result.discordMessageId, forwardBody);
  }
  return await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(inserted.id).first<MessageRow>() ?? inserted;
}

function readForwardFileUrl(metadata: string | null): string | undefined {
  const parsed = safeParse(metadata);
  if (!parsed || typeof parsed !== 'object') return undefined;
  const fileUrl = (parsed as Record<string, unknown>)['file_url'];
  return typeof fileUrl === 'string' && fileUrl.trim() ? fileUrl.trim() : undefined;
}

function buildForwardMetadata(sourceChannel: Channel | null, fileUrl?: string): Record<string, unknown> {
  const metadata: Record<string, unknown> = { forwarded_from_channel: sourceChannel ?? 'unknown' };
  if (fileUrl) metadata['file_url'] = fileUrl;
  return metadata;
}

function mergeDeliveryMetadata(
  metadata: Record<string, unknown>,
  result: { telegramMessageId?: number; discordMessageId?: string },
): Record<string, unknown> {
  if (result.telegramMessageId) metadata['telegram_message_id'] = result.telegramMessageId;
  if (result.discordMessageId) metadata['discord_message_id'] = result.discordMessageId;
  return metadata;
}

async function fetchForwardAvatar(env: Env, agentId: string): Promise<string | undefined> {
  const row = await env.DB
    .prepare('SELECT avatar_url FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ avatar_url: string | null }>();
  return row?.avatar_url ?? undefined;
}

async function fetchSessionLabel(env: Env, sessionId: string | null): Promise<string | null> {
  if (!sessionId) return null;
  const row = await env.DB
    .prepare('SELECT label FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ label: string | null }>();
  return row?.label ?? null;
}

async function ensureForwardTelegramTopic(
  env: Env,
  sessionId: string | null,
  agentName: string,
  sessionLabel: string | null,
  channelConfig: { channel: Channel; config: Record<string, unknown> },
): Promise<void> {
  if (channelConfig.channel !== 'telegram' || !sessionId) return;
  await ensureTopicForSession(env, sessionId, agentName, sessionLabel, requireTelegramConfig(channelConfig.config));
}

async function resolveForwardConfig(
  env: Env,
  sessionId: string | null,
  channelConfig: { channel: Channel; config: Record<string, unknown> },
): Promise<Record<string, unknown>> {
  if (channelConfig.channel !== 'discord' || !sessionId || !channelConfig.config['use_threads']) {
    return { ...channelConfig.config };
  }
  const session = await env.DB
    .prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ discord_thread_id: string | null }>();
  if (!session?.discord_thread_id) return { ...channelConfig.config };
  return {
    ...channelConfig.config,
    channel_id: session.discord_thread_id,
    thread_id: session.discord_thread_id,
  };
}
