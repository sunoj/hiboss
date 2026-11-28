// Persist agent reactions.
// Exports reactions sub-router mounted under /api/messages/:id.
// Depends on message-helpers, and shared types.

import { Hono } from 'hono';
import type { Env, MessageRow } from '../types';
import { apiAuth, getAgentId } from '../middleware/auth';
import { fetchMessageRow } from './message-helpers';
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
  await storeMessageReaction(c.env, message.id, 'agent', agentId, emoji);
  return c.json({ ok: true });
});

routes.get('/:id/reactions', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) return c.text('not found', 404);
  const meta = parseMeta(message);
  const reactions = meta['reactions'] as { emoji: string; user?: string }[] | undefined;
  return c.json({ reactions: reactions ?? [] });
});

export const reactionsRouter = routes;

function parseMeta(message: MessageRow): Record<string, unknown> {
  return message.metadata ? JSON.parse(message.metadata) as Record<string, unknown> : {};
}
