// Router that implements agent-facing messaging endpoints atop the D1 schema.
// Exports POST/GET/PATCH/poll handlers for /api/messages, plus reactions sub-router.
// Depends on Hono, the auth middleware, channel adapters, and shared types.

import { Hono, type Context } from 'hono';
import { logAudit } from '../audit';
import { apiAuth, getAgentId } from '../middleware/auth';
import type { Direction, Env, MessageRow, Status } from '../types';
import { propagateMessageEdit } from './message-edit';
import { forwardMessage, validateForwardChannel } from './message-forward';
import {
  buildFilters,
  clampNumber,
  delay,
  expireMessageOptions,
  fetchMessageRow,
  fetchMessageWithReplies,
  mapMessageRow,
  parsePriorityFilter,
  validateOption,
} from './message-helpers';
import { messageReplyRouter } from './message-reply';
import { messageSendRouter } from './message-send';
import { reactionsRouter } from './reactions';
export { insertMessageWithRecovery } from './message-send';

const MAX_LIMIT = 100;
const DEFAULT_TIMEOUT_SECONDS = 300;
const WAIT_INTERVAL_MS = 1000;
const VALID_TRANSITIONS: Record<string, string[]> = {
  sent: ['delivered', 'read', 'replied', 'expired'],
  delivered: ['read', 'replied', 'expired'],
  read: ['replied', 'expired'],
};
const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', apiAuth);

routes.route('/', messageSendRouter);

routes.get('/', async (c) => {
  const agentId = getAgentId(c);
  const unread = c.req.query('unread') === 'true';
  const directionParam = c.req.query('direction') || undefined;
  const direction = validateOption<Direction>(directionParam, ['agent_to_boss', 'boss_to_agent', 'agent_to_agent']);
  const statusParam = unread ? undefined : c.req.query('status') || undefined;
  const status = validateOption<Status>(statusParam, ['sent', 'delivered', 'read', 'replied']);
  const priorityFilter = parsePriorityFilter(c.req.query('priority'));
  const typeFilter = c.req.query('type') || undefined;
  const sessionFilter = c.req.query('session') || undefined;
  const fromFilter = c.req.query('from') || undefined;
  const targetSessionFilter = c.req.query('target_session') || undefined;
  const searchFilter = c.req.query('search') || undefined;
  const limit = clampNumber(c.req.query('limit'), 20, MAX_LIMIT);
  const offset = Math.max(Number(c.req.query('offset') ?? '0'), 0);
  const { where, binds } = buildFilters(agentId, direction, status, priorityFilter, typeFilter, sessionFilter, unread, fromFilter, targetSessionFilter, searchFilter);
  const rows = await c.env.DB
    .prepare(
      `SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label, sessions.branch AS session_branch, sessions.status AS session_status FROM (SELECT * FROM messages WHERE ${where}) messages LEFT JOIN api_keys ON api_keys.id = messages.agent_id LEFT JOIN sessions ON sessions.id = messages.session_id ORDER BY messages.created_at DESC LIMIT ? OFFSET ?`
    )
    .bind(...binds, limit, offset)
    .all<MessageRow>();
  const countRow = await c.env.DB
    .prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`)
    .bind(...binds)
    .first<{ total: number }>();
  return c.json({ messages: (rows.results ?? []).map(mapMessageRow), total: countRow?.total ?? 0 });
});

routes.get('/:id', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageWithReplies(c.env, agentId, c.req.param('id'));
  if (!message) {
    return c.text('not found', 404);
  }
  return c.json(message);
});

routes.route('/', messageReplyRouter);

routes.post('/:id/forward', async (c) => {
  const agentId = getAgentId(c);
  const original = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!original) {
    return c.text('not found', 404);
  }
  if (original.agent_id !== agentId) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const targetChannel = validateForwardChannel(payload.channel);
  if (!targetChannel) {
    return c.text('channel must be discord or telegram', 400);
  }
  try {
    const forwarded = await forwardMessage(c.env, original, targetChannel);
    c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'message.forward', 'message', original.id, targetChannel));
    return c.json(mapMessageRow(forwarded), 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'forward failed';
    const status = message === 'no channel configured' ? 400 : message === 'cannot forward boss messages' ? 403 : 502;
    return c.text(message, status);
  }
});

routes.patch('/:id', async (c) => {
  const agentId = getAgentId(c);
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : undefined;
  const status = validateOption<Status>(payload.status, ['sent', 'delivered', 'read', 'replied', 'expired']);
  if (!status && !body) {
    return c.text('status or body is required', 400);
  }
  const existing = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!existing) {
    return c.text('not found', 404);
  }
  const isTargetAgent = existing.direction === 'agent_to_agent' && existing.target_agent_id === agentId;
  if (existing.agent_id !== agentId && !isTargetAgent) {
    return c.text('only message owner can update message', 403);
  }
  if (body && existing.direction !== 'agent_to_boss') {
    return c.text('only agent_to_boss messages can be edited', 403);
  }
  if (isTargetAgent && (body || status !== 'read')) {
    return c.text('only message owner can update message', 403);
  }

  const updated = await updateMessage(c, existing, status, body);
  if (updated instanceof Response) return updated;
  if (!updated) {
    return c.text('update failed', 500);
  }
  if (body) {
    c.executionCtx.waitUntil(propagateMessageEdit(c.env, updated));
    c.executionCtx.waitUntil(
      logAudit(c.env, 'agent', agentId, 'message.edit', 'message', updated.id, JSON.stringify({ channel: updated.channel }))
    );
  }
  return c.json(mapMessageRow(updated));
});

// Bulk mark all unread messages as read
routes.post('/mark-all-read', async (c) => {
  const agentId = getAgentId(c);
  const result = await c.env.DB
    .prepare("UPDATE messages SET status = 'read', updated_at = datetime('now') WHERE ((agent_id = ? AND direction != 'agent_to_agent') OR target_agent_id = ?) AND status IN ('sent', 'delivered')")
    .bind(agentId, agentId)
    .run();
  const count = result.meta.changes ?? 0;
  return c.json({ marked: count });
});

// React and reactions endpoints are in reactions.ts
routes.route('/', reactionsRouter);

routes.post('/:id/poll', async (c) => {
  const agentId = getAgentId(c);
  const message = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!message) {
    return c.text('not found', 404);
  }
  if (message.mode !== 'blocking') {
    return c.text('not blocking message', 400);
  }
  const timeoutSec = clampNumber(c.req.query('timeout'), DEFAULT_TIMEOUT_SECONDS, DEFAULT_TIMEOUT_SECONDS);
  const deadline = Date.now() + timeoutSec * 1000;
  while (true) {
    const current = await fetchMessageWithReplies(c.env, agentId, message.id);
    if (current && (current.replies?.length ?? 0) > 0) {
      return c.json(current);
    }
    if (Date.now() >= deadline) {
      const finalCheck = await fetchMessageWithReplies(c.env, agentId, message.id);
      if (finalCheck && (finalCheck.replies?.length ?? 0) > 0) {
        return c.json(finalCheck);
      }
      c.executionCtx.waitUntil(expireMessageOptions(c.env, agentId, message).catch(() => {}));
      return c.json(finalCheck ?? { ...mapMessageRow(message), replies: [] });
    }
    await delay(Math.min(WAIT_INTERVAL_MS, deadline - Date.now()));
  }
});

export const messagesRouter = routes;

async function updateMessage(c: Context<{ Bindings: Env }>, existing: MessageRow, status: Status | null, body: string | undefined): Promise<Response | MessageRow | null> {
  const updates: string[] = ["updated_at = datetime('now')"];
  const binds: unknown[] = [];

  if (status) {
    const allowed = VALID_TRANSITIONS[existing.status];
    if (!allowed || !allowed.includes(status)) {
      return c.text(`invalid status transition from ${existing.status} to ${status}`, 400);
    }
    updates.push('status = ?');
    binds.push(status);
  }

  if (body) {
    updates.push('body = ?');
    binds.push(body);
  }

  binds.push(existing.id);

  const updated = await c.env.DB
    .prepare(
      `UPDATE messages SET ${updates.join(', ')} WHERE id = ? RETURNING *`
    )
    .bind(...binds)
    .first<MessageRow>();

  return updated;
}
