// Agent message creation, validation, targeting, and delivery orchestration.
// Exports messageSendRouter and idempotent insertion; depends on shared message helpers.
import { ownsSession } from '../projects';
import { Hono, type Context } from 'hono';
import { logAudit } from '../audit';
import { notifyBossAgents, notifyTargetAgent } from '../notify';
import { createMessageId, insertMessageWithEvent } from '../session-events';
import type { Channel, Direction, Env, MessageRow, Mode, Priority } from '../types';
import {
  expirePreviousOptions,
  findByIdempotencyKey,
  inferSessionStatus,
} from './message-helpers';
import { prepareSendInput, type SendInput } from './message-send-input';
import type { SendTarget } from './message-send-target';

import { dispatchDestinations } from '../delivery';
import { deliverLegacySend } from './message-send-legacy';
import { resolveSendTarget } from './message-send-target';
const DEFAULT_TIMEOUT_SECONDS = 300;
const routes = new Hono<{ Bindings: Env }>();
function isUniqueConstraintError(error: unknown): boolean {
  return error instanceof Error && error.message.includes('UNIQUE constraint failed');
}

export async function insertMessageWithRecovery(
  env: Env,
  agentId: string,
  values: [Direction, Mode, Channel | null, string, Priority, string, string | null, string | null, string | null, string | null, string | null]
): Promise<{ inserted: MessageRow | null; existing: MessageRow | null }> {
  const [direction, mode, channel, body, priority, messageType, idempotencyKey, metadataJson, sessionId, targetAgentId, targetSessionId] = values;
  const messageId = createMessageId();
  try {
    const inserted = await insertMessageWithEvent(
      env,
      'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, type, idempotency_key, metadata, session_id, target_agent_id, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
      [messageId, agentId, direction, mode, channel, body, 'sent', priority, messageType, idempotencyKey, metadataJson, sessionId, targetAgentId, targetSessionId],
      sessionId ?? targetSessionId,
    );
    return { inserted, existing: null };
  } catch (error) {
    if (!idempotencyKey || !isUniqueConstraintError(error)) throw error;
    const existing = await findByIdempotencyKey(env, agentId, idempotencyKey);
    if (existing) {
      return { inserted: null, existing };
    }
    throw error;
  }
}

routes.post('/', async (c) => {
  const input = await prepareSendInput(c);
  if (input instanceof Response) return input;
  const { toAgent, sessionId } = input;
  if (!await ownsSession(c.env.DB, sessionId, input.agentId)) return c.text('session does not belong to calling agent', 400);
  const target = await resolveSendTarget(c, toAgent, sessionId);
  if (target instanceof Response) return target;
  const inserted = await persistSend(c, input, target);
  if (inserted instanceof Response) return inserted;
  return finishSend(c, input, target, inserted);
});

async function persistSend(c: Context<{ Bindings: Env }>, input: SendInput, target: SendTarget): Promise<Response | MessageRow> {
  const { agentId, channelConfigs, requestedChannel, metadata, idempotencyKey, mode, body, priority, messageType, sessionId } = input;
  const { targetAgentId, targetSessionId, direction, targetSession } = target;
  // Agent-to-agent messages use 'api' channel; others use resolved channel config
  const channel = direction === 'agent_to_agent' ? 'api' : (channelConfigs[0]?.channel ?? requestedChannel ?? null);
  const metadataJson = metadata ? JSON.stringify(metadata) : null;
  if (idempotencyKey) {
    const existing = await findByIdempotencyKey(c.env, agentId, idempotencyKey);
    if (existing) {
      const response: Record<string, unknown> = { id: existing.id, status: existing.status, created_at: existing.created_at };
      if (targetSession) response.target = targetSession;
      return c.json(response, 200);
    }
  }
  const { inserted, existing } = await insertMessageWithRecovery(c.env, agentId, [
    direction,
    mode,
    channel,
    body,
    priority,
    messageType,
    idempotencyKey,
    metadataJson,
    sessionId,
    targetAgentId,
    targetSessionId,
  ]);
  if (existing) {
    const response: Record<string, unknown> = { id: existing.id, status: existing.status, created_at: existing.created_at };
    if (targetSession) response.target = targetSession;
    return c.json(response, 200);
  }
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  return inserted;
}

async function finishSend(c: Context<{ Bindings: Env }>, input: SendInput, target: SendTarget, inserted: MessageRow): Promise<Response> {
  const { agentId, payload, mode, priority, body, sessionId, options, channelConfigs, optionMediaResult, fileUrl, agentConfig } = input;
  const { direction, targetAgentId, targetSession, targetWarning } = target;
  // Set expires_at for messages with options (enables cron-based expiry sweep)
  if (options && inserted) {
    const timeoutSec = mode === 'blocking' && typeof payload.timeout === 'number'
      ? Math.max(60, Math.min(payload.timeout, 3600))
      : DEFAULT_TIMEOUT_SECONDS;
    const expiresAt = new Date(Date.now() + timeoutSec * 1000).toISOString();
    await c.env.DB.prepare('UPDATE messages SET expires_at = ? WHERE id = ?').bind(expiresAt, inserted.id).run();
  }
  // Auto-update session status based on message characteristics
  if (sessionId && direction === 'agent_to_boss') {
    c.executionCtx.waitUntil(inferSessionStatus(c.env, agentId, sessionId, mode, priority as string, body));
  }
  await dispatchDestinations(c.env, inserted, channelConfigs);
  const legacyResult = await deliverLegacySend(c, inserted, channelConfigs, options, optionMediaResult.value, fileUrl, agentConfig?.avatar_url ?? undefined);
  if (legacyResult instanceof Response) return legacyResult;
  const queuedForQuietHours = legacyResult;
  // Notify boss-agents and boss iOS devices after immediate agent-to-boss delivery.
  if (direction === 'agent_to_boss' && !queuedForQuietHours) {
    c.executionCtx.waitUntil(notifyBossAgents(c.env, agentId, inserted));
  }
  // Notify target agent for agent-to-agent messages via callback
  if (targetAgentId) {
    c.executionCtx.waitUntil(notifyTargetAgent(c.env, targetAgentId, inserted));
  }
  if (options && direction === 'agent_to_boss') {
    c.executionCtx.waitUntil(expirePreviousOptions(c.env, agentId, sessionId, inserted.id).catch(() => {}));
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'agent', agentId, 'message.send', 'message', inserted.id, JSON.stringify({ direction, priority, mode })));
  const response: Record<string, unknown> = { id: inserted.id, status: inserted.status, created_at: inserted.created_at };
  if (targetSession) response.target = targetSession;
  if (targetWarning) response.warning = targetWarning;
  return c.json(response, 201);
}

export const messageSendRouter = routes;
