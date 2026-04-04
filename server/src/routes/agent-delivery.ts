// Shared agent-to-boss delivery flow used by live sends and the scheduled queue.
// Exports one helper that prepares session routing and invokes the channel adapter.
// Depends on delivery primitives plus message/session channel helpers.

import type { Channel, Env } from '../types';
import { deliverToChannelWithOptions, deliverWithRetry, type DeliveryResult, requireTelegramConfig } from './delivery';
import { ensureThreadForSession, ensureTopicForAgent } from './message-options';
import { ensureTopicForSession } from './session-channels';

export interface AgentDeliveryRequest {
  agentId: string;
  agentName: string;
  body: string;
  sessionId: string | null;
  avatarUrl?: string;
  fileUrl?: string;
  inlineKeyboard?: { text: string; callback_data: string }[][];
}

export async function deliverAgentMessage(
  env: Env,
  channelConfig: { channel: Channel; config: Record<string, unknown> },
  request: AgentDeliveryRequest,
): Promise<DeliveryResult> {
  const sessionLabel = await fetchSessionLabel(env, request.sessionId);
  const displayName = sessionLabel ? `${sessionLabel} (${request.agentName})` : request.agentName;
  const effectiveConfig = await buildEffectiveConfig(env, channelConfig, request.sessionId);

  await ensureTopicForAgent(env, request.agentId, effectiveConfig);
  await ensureThreadForSession(env, request.agentId, request.sessionId, effectiveConfig, undefined);
  if (effectiveConfig.channel === 'telegram' && request.sessionId) {
    await ensureTopicForSession(
      env,
      request.sessionId,
      request.agentName,
      sessionLabel,
      requireTelegramConfig(effectiveConfig.config),
    );
  }

  const result = await deliverWithRetry(() =>
    deliverToChannelWithOptions(
      effectiveConfig.channel,
      effectiveConfig.config,
      displayName,
      request.body,
      request.inlineKeyboard,
      request.fileUrl,
      request.avatarUrl,
      env,
      request.sessionId,
    )
  );

  if (result.delivered && result.discordMessageId) {
    await ensureThreadForSession(env, request.agentId, request.sessionId, effectiveConfig, result.discordMessageId, request.body);
  }
  return result;
}

async function fetchSessionLabel(env: Env, sessionId: string | null): Promise<string | null> {
  if (!sessionId) return null;
  const row = await env.DB
    .prepare('SELECT label FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ label: string | null }>();
  return row?.label ?? null;
}

async function buildEffectiveConfig(
  env: Env,
  channelConfig: { channel: Channel; config: Record<string, unknown> },
  sessionId: string | null,
): Promise<{ channel: Channel; config: Record<string, unknown> }> {
  if (channelConfig.channel !== 'discord' || !sessionId || !channelConfig.config['use_threads']) {
    return { channel: channelConfig.channel, config: { ...channelConfig.config } };
  }
  const session = await env.DB
    .prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ discord_thread_id: string | null }>();
  if (!session?.discord_thread_id) {
    return { channel: channelConfig.channel, config: { ...channelConfig.config } };
  }
  return {
    channel: channelConfig.channel,
    config: {
      ...channelConfig.config,
      channel_id: session.discord_thread_id,
      thread_id: session.discord_thread_id,
    },
  };
}
