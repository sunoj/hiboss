// Agent reply endpoint and legacy reply delivery.
// Exports messageReplyRouter; depends on message helpers and destination dispatch.
import { Hono, type Context } from 'hono';
import { logAudit } from '../audit';
import { getAgentId, getAgentKeyId } from '../middleware/auth';
import { actionContent, audienceOf, authenticateAgentMessage, signedIdempotencyKey } from '../message-security';
import { findByIdempotencyKey } from './message-queries';
import { notifyBossAgents, notifyTargetAgent } from '../notify';
import { createMessageId, insertMessageWithEvent } from '../session-events';
import type { Direction, Env, MessageRow } from '../types';
import { OPEN_MESSAGE_STATUS } from '../message-status';
import { ownsSession } from '../projects';
import { isDecisionReply } from '../decision-answerability';

import { dispatchDestinations } from '../delivery';
import { fetchMessageRow, mapMessageRow, replyTargetSession } from './message-helpers';
import { enqueueNativeDelivery } from './message-send-legacy';
const routes = new Hono<{ Bindings: Env }>();
routes.post('/:id/reply', async (c) => {
  const agentId = getAgentId(c);
  const parent = await fetchMessageRow(c.env, agentId, c.req.param('id'));
  if (!parent) {
    return c.text('not found', 404);
  }
  const canReply = parent.direction === 'agent_to_agent'
    ? parent.agent_id === agentId || parent.target_agent_id === agentId
    : parent.agent_id === agentId;
  if (!canReply) {
    return c.text('forbidden', 403);
  }
  const payload = await c.req.json<Record<string, unknown>>();
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) {
    return c.text('body is required', 400);
  }
  // For agent_to_agent messages, reply direction is also agent_to_agent (back to sender)
  const replyDirection: Direction = parent.direction === 'agent_to_agent'
    ? 'agent_to_agent'
    : 'agent_to_boss';
  const replyTargetAgentId = replyDirection === 'agent_to_agent' ? parent.agent_id : null;
  const replyTargetSessionId = replyDirection === 'agent_to_agent' ? replyTargetSession(parent) : null;
  const audience = audienceOf(replyDirection, replyTargetAgentId, replyTargetSessionId);
  const auth = await authenticateAgentMessage({
    env: c.env, agentId, agentKeyId: getAgentKeyId(c), signedMessage: payload.signed_message,
    content: actionContent({ kind: 'reply', message_id: parent.id, audience }, body),
  });
  if (!auth.ok) return c.text(auth.error, auth.status);
  const idempotencyKey = auth.signed ? signedIdempotencyKey(auth.signed) : null;
  if (idempotencyKey) {
    const existing = await findByIdempotencyKey(c.env, agentId, idempotencyKey);
    if (existing) return c.json(mapMessageRow(existing), 200);
  }
  const sessionId = await replierSession(c.env, parent, agentId);
  return persistReply(c, parent, body, replyDirection, { agentId: replyTargetAgentId, sessionId: replyTargetSessionId },
    sessionId, auth.metadata, idempotencyKey);
});

/**
 * The replier's own session, which owns the reply row and its event: the parent's session for
 * the agent's own conversation, the addressed session for a peer message, null otherwise.
 */
async function replierSession(env: Env, parent: MessageRow, agentId: string): Promise<string | null> {
  if (parent.direction !== 'agent_to_agent') return replyTargetSession(parent);
  const candidate = parent.agent_id === agentId ? parent.session_id
    : parent.target_agent_id === agentId ? parent.target_session_id : null;
  return candidate && await ownsSession(env.DB, candidate, agentId) ? candidate : null;
}

async function persistReply(
  c: Context<{ Bindings: Env }>, parent: MessageRow, body: string, replyDirection: Direction,
  target: { agentId: string | null; sessionId: string | null }, sessionId: string | null,
  metadata: Record<string, unknown>, idempotencyKey: string | null,
): Promise<Response> {
  const agentId = getAgentId(c);
  const replyTargetAgentId = target.agentId;
  const inserted = await insertMessageWithEvent(
    c.env,
    `INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority,
      session_id, reply_to, target_agent_id, target_session_id, metadata, idempotency_key)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *`,
    [createMessageId(), agentId, replyDirection, 'async', replyDirection === 'agent_to_agent' ? 'api' : null, body, 'sent', 'normal',
      sessionId, parent.id, replyTargetAgentId, target.sessionId,
      JSON.stringify(metadata), idempotencyKey],
    sessionId,
  );
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  if (replyDirection === 'agent_to_boss') {
    await dispatchDestinations(c.env, inserted);
    if (!await enqueueNativeDelivery(c.env, inserted)) {
      c.executionCtx.waitUntil(notifyBossAgents(c.env, agentId, inserted));
    }
  }
  // Only an answer closes the parent; the asker's own follow-ups leave its ask open.
  if (parent.direction !== 'agent_to_boss' && isDecisionReply(parent, inserted)) {
    await c.env.DB
      .prepare(`UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ? AND ${OPEN_MESSAGE_STATUS}`)
      .bind(parent.id).run();
  }
  if (replyTargetAgentId) {
    c.executionCtx.waitUntil(notifyTargetAgent(c.env, replyTargetAgentId, inserted));
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'message.reply', 'message', parent.id));
  return c.json(mapMessageRow(inserted), 201);
}

export const messageReplyRouter = routes;
