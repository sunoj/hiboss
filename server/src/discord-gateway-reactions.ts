// Discord gateway DB helpers for channel lookup and reaction persistence.
// Exports: lookupDiscordAgentId, persistDiscordReaction, DiscordReactionChangeData.
// Deps: Env binding and D1-backed messages/channel_configs/sessions tables.

import type { Env } from './types';

export interface DiscordReactionChangeData {
  user_id: string;
  channel_id: string;
  message_id: string;
  emoji: { id: string | null; name: string };
}

type DiscordMessageRow = {
  id: string;
  metadata: string | null;
};

type DiscordReaction = {
  emoji: string;
  user: string;
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
  const message = await findDiscordMessage(env, agentId, reaction.message_id);
  if (!message) {
    return false;
  }
  const metadata = parseMetadata(message.metadata);
  const reactions = readReactions(metadata['reactions']);
  metadata['reactions'] = action === 'add'
    ? [...reactions, toReactionRecord(reaction)]
    : reactions.filter((entry) => !matchesReaction(entry, reaction));
  await env.DB.prepare('UPDATE messages SET metadata = ? WHERE id = ?').bind(JSON.stringify(metadata), message.id).run();
  return true;
}

async function findDiscordMessage(env: Env, agentId: string, discordMessageId: string): Promise<DiscordMessageRow | null> {
  return env.DB
    .prepare("SELECT id, metadata FROM messages WHERE agent_id = ? AND channel = 'discord' AND (json_extract(metadata, '$.discord_message_id') = ? OR json_extract(metadata, '$.discord_msg.id') = ?) LIMIT 1")
    .bind(agentId, discordMessageId, discordMessageId)
    .first<DiscordMessageRow>();
}

function parseMetadata(metadata: string | null): Record<string, unknown> {
  if (!metadata) {
    return {};
  }
  try {
    return JSON.parse(metadata) as Record<string, unknown>;
  } catch {
    return {};
  }
}

function readReactions(value: unknown): DiscordReaction[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.flatMap((entry) => {
    if (!entry || typeof entry !== 'object') {
      return [];
    }
    const emoji = 'emoji' in entry && typeof entry.emoji === 'string' ? entry.emoji : null;
    const user = 'user' in entry && typeof entry.user === 'string' ? entry.user : null;
    return emoji && user ? [{ emoji, user }] : [];
  });
}

function toReactionRecord(reaction: DiscordReactionChangeData): DiscordReaction {
  return { emoji: reaction.emoji.name, user: reaction.user_id };
}

function matchesReaction(entry: DiscordReaction, reaction: DiscordReactionChangeData): boolean {
  return entry.emoji === reaction.emoji.name && entry.user === reaction.user_id;
}
