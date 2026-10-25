// Discord gateway DB helpers for channel lookup and reaction persistence.
// Exports: lookupDiscordAgentId, persistDiscordReaction, DiscordReactionChangeData.
// Deps: Env binding and D1-backed messages/channel_configs/sessions tables.

import type { Env } from './types';
import { storeMessageReaction, removeMessageReaction } from './routes/message-reactions';
import { checkBossPermission } from './routes/webhook-helpers';

export interface DiscordReactionChangeData {
  user_id: string;
  channel_id: string;
  message_id: string;
  emoji: { id: string | null; name: string };
}

type DiscordMessageRow = {
  id: string;
};

export async function lookupDiscordAgentId(env: Env, channelId: string): Promise<string | null> {
  const direct = await env.DB
    .prepare("SELECT agent_id FROM channel_configs WHERE channel = 'discord' AND enabled = 1 AND json_extract(config, '$.channel_id') = ? LIMIT 1")
    .bind(channelId)
    .first<{ agent_id: string }>();
  if (direct) {
    return direct.agent_id;
  }
  const threadSession = await env.DB
    .prepare('SELECT agent_id FROM sessions WHERE discord_thread_id = ? LIMIT 1')
    .bind(channelId)
    .first<{ agent_id: string }>();
  if (!threadSession) {
    return null;
  }
  const config = await env.DB
    .prepare("SELECT agent_id FROM channel_configs WHERE agent_id = ? AND channel = 'discord' AND enabled = 1 LIMIT 1")
    .bind(threadSession.agent_id)
    .first<{ agent_id: string }>();
  return config?.agent_id ?? null;
}

export async function persistDiscordReaction(
  env: Env,
  agentId: string,
  reaction: DiscordReactionChangeData,
  action: 'add' | 'remove'
): Promise<boolean> {
  const permission = await checkBossPermission(env, 'discord', reaction.user_id, agentId, true);
  if (permission.error || !permission.boss || permission.boss.role === 'viewer') return false;
  const message = await findDiscordMessage(env, agentId, reaction.message_id);
  if (!message) {
    return false;
  }
  if (action === 'add') {
    await storeMessageReaction(env, message.id, 'boss', reaction.user_id, reaction.emoji.name);
  } else {
    await removeMessageReaction(env, message.id, 'boss', reaction.user_id, reaction.emoji.name);
  }
  return true;
}

async function findDiscordMessage(
  env: Env, agentId: string, discordMessageId: string,
): Promise<DiscordMessageRow | null> {
  return env.DB
    .prepare(`SELECT id FROM messages WHERE agent_id = ? AND channel = 'discord' AND
      (json_extract(metadata, '$.discord_message_id') = ?
        OR json_extract(metadata, '$.discord_msg.id') = ?) LIMIT 1`)
    .bind(agentId, discordMessageId, discordMessageId)
    .first<DiscordMessageRow>();
}
