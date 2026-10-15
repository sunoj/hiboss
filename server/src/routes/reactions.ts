// Persist agent reactions on every channel and forward to Discord or Telegram.
// Exports reactions sub-router mounted under /api/messages/:id.
// Depends on channel adapters, message-helpers, and shared types.

import { Hono } from 'hono';
import type { Env, MessageRow } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { setTelegramReaction } from '../channels/telegram';
import { addDiscordReaction, getDiscordReactions } from '../channels/discord';
import {
  extractTelegramMessageId,
  fetchMessageRow,
  requireTelegramConfig,
  selectChannelConfig,
} from './message-helpers';
import { resolveDiscordChannelId } from './agent-delivery';
import { storeMessageReaction } from './message-reactions';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.post('/:id/react', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) return c.text('not found', 404);
  const payload = await c.req.json<Record<string, unknown>>();
  const emoji = typeof payload.emoji === 'string' ? payload.emoji.trim() : '';
  if (!emoji) return c.text('emoji is required', 400);
  const added = await storeMessageReaction(c.env, message.id, 'agent', agentId, emoji);
  if (added) {
    try {
      await forwardReaction(c.env, agentId, message, emoji);
    } catch {
      return c.json({ ok: true, forwarded: false });
    }
  }
  return c.json({ ok: true });
});

async function forwardReaction(env: Env, agentId: string, message: MessageRow, emoji: string): Promise<void> {
  const meta = parseMeta(message);
  if (message.channel === 'telegram') {
    const telegramMsgId = extractTelegramMessageId(message.metadata);
    if (!telegramMsgId) throw new Error('no telegram message id found');
    const cc = await selectChannelConfig(env, agentId, 'telegram');
    const tgConfig = requireTelegramConfig(cc.config);
    await setTelegramReaction(tgConfig.bot_token, tgConfig.chat_id, telegramMsgId, emoji);
    return;
  }
  if (message.channel === 'discord') {
    const discordMsgId = typeof meta['discord_message_id'] === 'string' ? meta['discord_message_id']
      : typeof (meta['discord_msg'] as Record<string, unknown> | undefined)?.['id'] === 'string' ? (meta['discord_msg'] as Record<string, unknown>)['id'] as string
      : undefined;
    if (!discordMsgId) throw new Error('no discord message id found');
    const cc = await selectChannelConfig(env, agentId, 'discord');
    const botToken = typeof cc.config['bot_token'] === 'string' ? cc.config['bot_token'] : undefined;
    // Messages post into the session thread (when enabled), so react there — not the parent channel.
    const channelId = await resolveDiscordChannelId(env, cc.config, message.session_id ?? null);
    if (!botToken || !channelId) throw new Error('discord bot_token and channel_id required for reactions');
    await addDiscordReaction(botToken, channelId, discordMsgId, emoji);
    return;
  }
}

routes.get('/:id/reactions', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) return c.text('not found', 404);
  const meta = parseMeta(message);
  if (message.channel === 'discord') {
    const discordMsgId = typeof meta['discord_message_id'] === 'string' ? meta['discord_message_id']
      : typeof (meta['discord_msg'] as Record<string, unknown> | undefined)?.['id'] === 'string' ? (meta['discord_msg'] as Record<string, unknown>)['id'] as string
      : undefined;
    if (!discordMsgId) return c.json({ reactions: [] });
    const cc = await selectChannelConfig(c.env, agentId, 'discord');
    const botToken = typeof cc.config['bot_token'] === 'string' ? cc.config['bot_token'] : undefined;
    const channelId = await resolveDiscordChannelId(c.env, cc.config, message.session_id ?? null);
    if (!botToken || !channelId) return c.json({ reactions: [] });
    const reactions = await getDiscordReactions(botToken, channelId, discordMsgId);
    return c.json({ reactions });
  }
  const reactions = meta['reactions'] as { emoji: string; user?: string }[] | undefined;
  return c.json({ reactions: reactions ?? [] });
});

export const reactionsRouter = routes;

function parseMeta(message: MessageRow): Record<string, unknown> {
  return message.metadata ? JSON.parse(message.metadata) as Record<string, unknown> : {};
}
