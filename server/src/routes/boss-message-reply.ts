// Handles boss replies with optional paired-device signature enforcement.
// Exports a focused router mounted before the broader boss API router.
// Depends on boss auth, access checks, message options, and provenance verification.

import { Hono, type Context } from 'hono';
import type { Env, MessageRow } from '../types';
import {
  bossAuth, getBossId, getBossName, getBossRole, getBossTokenId,
} from '../middleware/auth';
import { authenticateBossReply } from '../message-security';
import { createMessageId, insertMessageWithEvent } from '../session-events';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { claimOptionReply } from './boss-option-reply';
import { getAccessibleAgentIds } from './boss-api';
import { escapeLike } from './bosses';
import { mapMessageRow, replyTargetSession } from './message-helpers';
import { withdrawResolvedOptions } from './message-options';

type BossContext = Context<{ Bindings: Env }>;
const routes = new Hono<{ Bindings: Env }>({});
routes.use('*', bossAuth);
routes.post('/messages/:id/reply', handleReply);

async function handleReply(c: BossContext): Promise<Response> {
  const role = getBossRole(c);
  if (role === 'viewer') return c.text('viewer cannot send messages', 403);
  const parent = await findParent(c);
  if (!parent) return c.text('not found', 404);
  const payload = await parsePayload(c);
  if (!payload?.body) return c.text('body is required', 400);
  const bossId = getBossId(c);
  const authenticated = await authenticateBossReply({
    env: c.env, bossId, bossName: getBossName(c), tokenId: getBossTokenId(c),
    parentMessageId: parent.id, body: payload.body, signedMessage: payload.signedMessage,
  });
  if (!authenticated.ok) return c.text(authenticated.error, authenticated.status);
  const duplicate = await findDuplicate(c.env, parent.agent_id, authenticated.value.idempotencyKey);
  if (duplicate) return c.json(mapMessageRow(duplicate));
  const optionClaim = await claimOptionReply(c.env, parent, authenticated.value.body, true);
  if (optionClaim.kind === 'resolved') return c.text('option already resolved', 409);
  const inserted = await insertReply(c.env, parent, authenticated.value);
  if (!inserted) return c.text('failed to persist', 500);
  finishReply(c, parent, inserted, optionClaim.kind, bossId, getBossName(c));
  return c.json(mapMessageRow(inserted), 201);
}

async function findParent(c: BossContext): Promise<MessageRow | null> {
  const bossId = getBossId(c);
  const agentIds = await getAccessibleAgentIds(c.env, bossId, getBossRole(c));
  const id = c.req.param('id') ?? '';
  const row = await c.env.DB.prepare(
    "SELECT * FROM messages WHERE id = ? OR id LIKE ? ESCAPE '\\'",
  ).bind(id, `${escapeLike(id)}%`).first<MessageRow>();
  return row && agentIds.includes(row.agent_id) ? row : null;
}

async function parsePayload(c: BossContext): Promise<{
  body: string;
  signedMessage?: unknown;
} | null> {
  try {
    const value = await c.req.json<unknown>();
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    const record = value as Record<string, unknown>;
    const body = typeof record.body === 'string' ? record.body.trim() : '';
    return { body, ...(record.signed_message !== undefined
      ? { signedMessage: record.signed_message } : {}) };
  } catch {
    return null;
  }
}

async function findDuplicate(
  env: Env,
  agentId: string,
  idempotencyKey: string | null,
): Promise<MessageRow | null> {
  if (!idempotencyKey) return null;
  return env.DB.prepare(
    'SELECT * FROM messages WHERE agent_id = ? AND idempotency_key = ?',
  ).bind(agentId, idempotencyKey).first<MessageRow>();
}

async function insertReply(
  env: Env,
  parent: MessageRow,
  authenticated: { body: string; idempotencyKey: string | null; provenance: Record<string, unknown> },
): Promise<MessageRow | null> {
  const targetSession = replyTargetSession(parent);
  return insertMessageWithEvent(
    env,
    `INSERT INTO messages
       (id, agent_id, direction, mode, channel, body, status, priority, reply_to,
        idempotency_key, metadata, target_session_id)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *`,
    [createMessageId(), parent.agent_id, 'boss_to_agent', 'async', 'api',
      authenticated.body, 'sent', 'normal', parent.id, authenticated.idempotencyKey,
      JSON.stringify(authenticated.provenance), targetSession],
    targetSession,
  );
}

function finishReply(
  c: BossContext,
  parent: MessageRow,
  inserted: MessageRow,
  optionKind: 'not_option' | 'invalid_choice' | 'claimed',
  bossId: string,
  bossName: string,
): void {
  if (optionKind === 'not_option') {
    c.executionCtx.waitUntil(c.env.DB.prepare(
      "UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?",
    ).bind(parent.id).run());
  }
  if (optionKind === 'claimed') {
    c.executionCtx.waitUntil(
      withdrawResolvedOptions(c.env, parent.agent_id, parent, inserted.body).catch(() => {}),
    );
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, parent.agent_id, inserted));
  c.executionCtx.waitUntil(
    logAudit(c.env, 'boss', bossId, 'message.reply', 'message', parent.id, bossName),
  );
}

export const bossMessageReplyRouter = routes;
