// React and reactions endpoints for Discord and Telegram messages.
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
  requireDiscordConfig,
  requireTelegramConfig,
  selectChannelConfig,
} from './message-helpers';

const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.post('/:id/react', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) return c.text('not found', 404);
  const payload = await c.req.json<Record<string, unknown>>();
  const emoji = typeof payload.emoji === 'string' ? payload.emoji.trim() : '';
  if (!emoji) return c.text('emoji is required', 400);
  const meta = parseMeta(message);
  if (message.channel === 'telegram') {
    const telegramMsgId = extractTelegramMessageId(message.metadata);
    if (!telegramMsgId) return c.text('no telegram message id found', 400);
    const cc = await selectChannelConfig(c.env, agentId, 'telegram');
    const tgConfig = requireTelegramConfig(cc.config);
    await setTelegramReaction(tgConfig.bot_token, tgConfig.chat_id, telegramMsgId, emoji);
    return c.json({ ok: true });
  }
  if (message.channel === 'discord') {
    const discordMsgId = typeof meta['discord_message_id'] === 'string' ? meta['discord_message_id'] : undefined;
    if (!discordMsgId) return c.text('no discord message id found', 400);
    const cc = await selectChannelConfig(c.env, agentId, 'discord');
    const dc = requireDiscordConfig(cc.config);
    if (!dc.bot_token || !dc.channel_id) return c.text('discord bot_token and channel_id required for reactions', 400);
    await addDiscordReaction(dc.bot_token, dc.channel_id, discordMsgId, emoji);
    return c.json({ ok: true });
  }
  return c.text('reactions not supported on this channel', 400);
});

routes.get('/:id/reactions', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) return c.text('not found', 404);
  const meta = parseMeta(message);
  if (message.channel === 'discord') {
    const discordMsgId = typeof meta['discord_message_id'] === 'string' ? meta['discord_message_id'] : undefined;
    if (!discordMsgId) return c.json({ reactions: [] });
    const cc = await selectChannelConfig(c.env, agentId, 'discord');
    const dc = requireDiscordConfig(cc.config);
    if (!dc.bot_token || !dc.channel_id) return c.json({ reactions: [] });
    const reactions = await getDiscordReactions(dc.bot_token, dc.channel_id, discordMsgId);
    return c.json({ reactions });
  }
  const reactions = meta['reactions'] as { emoji: string; user?: string }[] | undefined;
  return c.json({ reactions: reactions ?? [] });
});

export const reactionsRouter = routes;

function parseMeta(message: MessageRow): Record<string, unknown> {
  return message.metadata ? JSON.parse(message.metadata) as Record<string, unknown> : {};
}
