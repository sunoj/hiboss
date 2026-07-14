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
  const base = { channel: channelConfig.channel, config: { ...channelConfig.config } };
  if (channelConfig.channel !== 'discord') return base;
  const threadChannel = await resolveDiscordChannelId(env, channelConfig.config, sessionId);
  if (!threadChannel || threadChannel === channelConfig.config['channel_id']) return base;
  return {
    channel: channelConfig.channel,
    config: { ...channelConfig.config, channel_id: threadChannel, thread_id: threadChannel },
  };
}

/**
 * Resolve the Discord channel a session's messages actually land in.
 * With thread routing on, messages post into the session's thread, so
 * reactions/edits must target that thread id, not the parent channel_id.
 * Falls back to the config's channel_id when there's no session thread.
 */
export async function resolveDiscordChannelId(
  env: Env,
  config: Record<string, unknown>,
  sessionId: string | null,
): Promise<string | undefined> {
  const base = typeof config['channel_id'] === 'string' ? config['channel_id'] : undefined;
  if (!sessionId || !config['use_threads']) return base;
  const session = await env.DB
    .prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ discord_thread_id: string | null }>();
  return session?.discord_thread_id ?? base;
}
