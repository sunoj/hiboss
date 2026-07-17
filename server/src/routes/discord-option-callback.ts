// Resolves Discord option buttons atomically across every Boss channel.
// Exports: handleDiscordOptionCallback for the interactions router.
// Dependencies: D1, Boss option claiming, permissions, callbacks, and audit.

import type { Context } from 'hono';
import { logAudit } from '../audit';
import { notifyAgentCallback } from '../notify';
import type { Env, MessageRow } from '../types';
import { claimOptionReply } from './boss-option-reply';
import { withdrawResolvedOptions } from './message-options';
import { checkBossPermission, findDiscordAgent } from './webhook-helpers';

interface DiscordOptionPayload {
  member?: { user?: { id?: string } };
  message?: { content?: string };
}

export async function handleDiscordOptionCallback(
  c: Context<{ Bindings: Env }>,
  payload: DiscordOptionPayload,
  customId: string,
  channelId: string,
): Promise<Response> {
  const selection = parseSelection(customId);
  if (!selection) return c.text('invalid custom_id format', 400);
  const agentRow = await findDiscordAgent(c.env, channelId);
  if (!agentRow) {
    return c.json({ type: 4, data: { content: 'No agent configured for this channel.', flags: 64 } });
  }
  const userId = payload.member?.user?.id;
  const permission = await checkBossPermission(c.env, 'discord', userId, agentRow.agent_id, true);
  if (permission.error) {
    return c.json({ type: 4, data: { content: permission.error, flags: 64 } });
  }
  const parent = await findParent(c.env, selection.messagePrefix, agentRow.agent_id);
  if (!parent) return c.text('message not found', 404);
  if (parent.status === 'expired') return expiredResponse(c);

  const claim = await claimOptionReply(c.env, parent, selection.option, false);
  if (claim.kind === 'invalid_choice') return c.text('invalid selection', 400);
  if (claim.kind === 'resolved') return resolvedResponse(c, payload.message?.content);
  const reply = await insertReply(c.env, parent, selection.option, agentRow.agent_id);
  if (!reply) return c.text('failed to persist', 500);
  if (claim.kind === 'not_option') await markParentReplied(c.env, parent.id);
  if (claim.kind === 'claimed') {
    c.executionCtx.waitUntil(
      withdrawResolvedOptions(c.env, agentRow.agent_id, parent, selection.option).catch(() => {}),
    );
  }

  c.executionCtx.waitUntil(notifyAgentCallback(c.env, agentRow.agent_id, reply));
  const actor = permission.boss ? 'boss' : 'system';
  const actorId = permission.boss?.id ?? 'discord';
  c.executionCtx.waitUntil(logAudit(c.env, actor, actorId, 'message.callback', 'message', parent.id, selection.option));
  return selectedResponse(c, payload.message?.content, selection.option);
}

function parseSelection(customId: string): { messagePrefix: string; option: string } | null {
  const colonIndex = customId.indexOf(':');
  if (colonIndex < 1) return null;
  const messagePrefix = customId.slice(0, colonIndex);
  const option = customId.slice(colonIndex + 1);
  if (!option || !/^[0-9a-f]{8,}$/i.test(messagePrefix)) return null;
  return { messagePrefix, option };
}

async function findParent(
  env: Env,
  messagePrefix: string,
  agentId: string,
): Promise<MessageRow | null> {
  return env.DB
    .prepare('SELECT * FROM messages WHERE id LIKE ? AND agent_id = ? LIMIT 1')
    .bind(`${messagePrefix}%`, agentId)
    .first<MessageRow>();
}

async function insertReply(
  env: Env,
  parent: Pick<MessageRow, 'id' | 'metadata'>,
  option: string,
  agentId: string,
): Promise<MessageRow | null> {
  const metadata = getActionMetadata(parent.metadata, option);
  return env.DB.prepare(
    'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
  ).bind(agentId, 'boss_to_agent', 'async', 'discord', option, 'sent', 'normal', parent.id, metadata)
    .first<MessageRow>();
}

async function markParentReplied(env: Env, messageId: string): Promise<void> {
  await env.DB.prepare("UPDATE messages SET status = 'replied', updated_at = datetime('now') WHERE id = ?")
    .bind(messageId).run();
}

function getActionMetadata(metadata: string | null, option: string): string | null {
  if (!metadata) return null;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    const actions = parsed['actions'] as Record<string, string> | undefined;
    return actions?.[option] ? JSON.stringify({ action: actions[option] }) : null;
  } catch {
    return null;
  }
}

function expiredResponse(c: Context<{ Bindings: Env }>): Response {
  return c.json({ type: 4, data: { content: '⏰ Options expired', flags: 64 } });
}

function resolvedResponse(c: Context<{ Bindings: Env }>, content: string | undefined): Response {
  return c.json({ type: 7, data: { content: appendResult(content, '⚠️ Already selected elsewhere'), components: [] } });
}

function selectedResponse(c: Context<{ Bindings: Env }>, content: string | undefined, option: string): Response {
  return c.json({ type: 7, data: { content: appendResult(content, `✅ Selected: ${option}`), components: [] } });
}

function appendResult(content: string | undefined, result: string): string {
  return content ? `${content}\n\n${result}` : result;
}
