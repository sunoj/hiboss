// Shared helpers for webhook route handlers: boss auth, routing rules, utils.
// Exports boss lookup, routing evaluation, and message mapping helpers.
// Depends on Env typings and D1 bindings.

import type { Env, MessageResponse, MessageRow } from '../types';
import { createMessageId, insertMessageWithEvent } from '../session-events';
import { channelMetadata, mergeProvenance } from '../message-security';

export function asString(value: unknown): string | undefined {
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return value.toString();
  return undefined;
}

export function mapMessage(row: MessageRow): MessageResponse {
  return { ...row, metadata: safeJson(row.metadata) };
}

export async function findEnabledChannelConfig(
  env: Env,
  channel: 'telegram' | 'discord',
  externalId: string
): Promise<{ agent_id: string; config: string } | null> {
  const path = channel === 'telegram' ? '$.chat_id' : '$.channel_id';
  const row = await env.DB
    .prepare(`SELECT agent_id, config FROM channel_configs WHERE channel = ? AND enabled = 1 AND json_extract(config, '${path}') = ? LIMIT 1`)
    .bind(channel, externalId)
    .first<{ agent_id: string; config: string }>();
  return row ?? null;
}

export async function findMessageByIdempotencyKey(env: Env, agentId: string, key: string): Promise<MessageRow | null> {
  const row = await env.DB
    .prepare('SELECT * FROM messages WHERE agent_id = ? AND idempotency_key = ? LIMIT 1')
    .bind(agentId, key)
    .first<MessageRow>();
  return row ?? null;
}

function safeJson(value: string | null): Record<string, unknown> | null {
  if (!value) return null;
  try {
    return JSON.parse(value) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export async function evaluateRoutingRules(env: Env, channel: string, body: string, defaultAgentId: string): Promise<string | null> {
  const rules = await env.DB
    .prepare('SELECT target_agent_id, pattern FROM routing_rules WHERE channel = ? AND owner_id = ? AND enabled = 1 ORDER BY priority DESC')
    .bind(channel, defaultAgentId)
    .all<{ target_agent_id: string; pattern: string }>();
  for (const rule of rules.results ?? []) {
    try {
      if (new RegExp(rule.pattern).test(body)) {
        return rule.target_agent_id !== defaultAgentId ? rule.target_agent_id : null;
      }
    } catch { /* skip invalid regex */ }
  }
  return null;
}

export async function findDiscordAgent(env: Env, channelId: string): Promise<{ agent_id: string } | null> {
  const direct = await findEnabledChannelConfig(env, 'discord', channelId);
  if (direct) {
    return { agent_id: direct.agent_id };
  }
  const threadSession = await env.DB
    .prepare('SELECT agent_id FROM sessions WHERE discord_thread_id = ? LIMIT 1')
    .bind(channelId)
    .first<{ agent_id: string }>();
  if (!threadSession) {
    return null;
  }
  return env.DB
    .prepare("SELECT agent_id FROM channel_configs WHERE agent_id = ? AND channel = 'discord' AND enabled = 1 LIMIT 1")
    .bind(threadSession.agent_id)
    .first<{ agent_id: string }>();
}

type BossLookupError = 'unknown sender' | 'viewer cannot send messages';

export async function resolveBossForChannel(
  env: Env,
  channel: 'telegram' | 'discord',
  userId: string | undefined,
  allowViewer: boolean
): Promise<{ boss: { id: string; name: string; role: string } | null; error?: BossLookupError }> {
  if ((await countBosses(env)) === 0) return { boss: null };
  if (!userId) return { boss: null, error: 'unknown sender' };
  const boss = await identifyBoss(env, channel, userId);
  if (!boss) return { boss: null, error: 'unknown sender' };
  if (!allowViewer && boss.role === 'viewer') return { boss: null, error: 'viewer cannot send messages' };
  return { boss };
}

async function identifyBoss(
  env: Env,
  channel: 'telegram' | 'discord',
  userId: string
): Promise<{ id: string; name: string; role: string } | null> {
  const col = channel === 'telegram' ? 'telegram_user_id' : 'discord_user_id';
  const row = await env.DB
    .prepare(`SELECT id, name, role FROM bosses WHERE ${col} = ? LIMIT 1`)
    .bind(userId)
    .first<{ id: string; name: string; role: string }>();
  return row ?? null;
}

export async function hasBossAccess(env: Env, bossId: string, agentId: string, bossRole: string): Promise<boolean> {
  if (bossRole === 'admin') return true;
  const row = await env.DB
    .prepare('SELECT 1 AS present FROM boss_agent_access WHERE boss_id = ? AND agent_id = ? LIMIT 1')
    .bind(bossId, agentId)
    .first<{ present: number }>();
  return !!row;
}

export async function checkBossPermission(
  env: Env,
  channel: 'discord' | 'telegram',
  userId: string | undefined,
  agentId: string,
  allowViewer: boolean
): Promise<{ boss: { id: string; name: string; role: string } | null; error?: string }> {
  const { boss, error } = await resolveBossForChannel(env, channel, userId, allowViewer);
  if (error === 'unknown sender') return { boss: null, error: 'Unknown sender' };
  if (error === 'viewer cannot send messages') return { boss: null, error: 'Viewer cannot send messages' };
  if (boss && !(await hasBossAccess(env, boss.id, agentId, boss.role))) {
    return { boss: null, error: 'No access to this agent' };
  }
  return { boss };
}

async function countBosses(env: Env): Promise<number> {
  const row = await env.DB
    .prepare('SELECT COUNT(*) AS total FROM bosses')
    .first<{ total: number }>();
  return row?.total ?? 0;
}

/** Shared logic: insert a boss → agent Discord message with precise reply linking. */
export async function insertBossDiscordMessage(
  env: Env,
  channelId: string,
  text: string,
  senderUserId: string | undefined,
  replyToDiscordMsgId: string | undefined,
  idempotencyKey: string | undefined,
  rawMetadata: Record<string, unknown>
): Promise<MessageRow | null> {
  let agentRow = await findEnabledChannelConfig(env, 'discord', channelId);
  let sessionId: string | null = null;
  if (!agentRow) {
    const threadSession = await env.DB
      .prepare('SELECT s.agent_id, s.id AS session_id FROM sessions s WHERE s.discord_thread_id = ? LIMIT 1')
      .bind(channelId)
      .first<{ agent_id: string; session_id: string }>();
    if (threadSession) {
      sessionId = threadSession.session_id;
      const cc = await env.DB
        .prepare("SELECT agent_id, config FROM channel_configs WHERE agent_id = ? AND channel = 'discord' AND enabled = 1 LIMIT 1")
        .bind(threadSession.agent_id)
        .first<{ agent_id: string; config: string }>();
      if (cc) {
        agentRow = cc;
      }
    }
  }
  if (!agentRow) {
    console.error('[webhook] discord message rejected: no agent found for channel', channelId);
    return null;
  }
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(env, 'discord', senderUserId, false);
  if (bossError) {
    console.error('[webhook] discord message rejected:', bossError);
    return null;
  }
  if (idempotencyKey) {
    const existing = await findMessageByIdempotencyKey(env, agentRow.agent_id, idempotencyKey);
    if (existing) return existing;
  }
  const routedAgentId = await evaluateRoutingRules(env, 'discord', text, agentRow.agent_id);
  if (routedAgentId) agentRow.agent_id = routedAgentId;
  if (bossInfo && !(await hasBossAccess(env, bossInfo.id, agentRow.agent_id, bossInfo.role))) return null;
  // Extract discord_message_id from raw Discord payload for reactions support
  const discordMsgPayload = rawMetadata['discord_msg'] as Record<string, unknown> | undefined;
  const discordMessageId = typeof discordMsgPayload?.['id'] === 'string' ? discordMsgPayload['id'] as string : undefined;
  const baseMetadata = discordMessageId ? { ...rawMetadata, discord_message_id: discordMessageId } : rawMetadata;
  const metadata = mergeProvenance(
    baseMetadata,
    channelMetadata('discord', bossInfo, senderUserId),
  );
  // Precise reply linking: look up parent by discord_message_id in metadata
  let replyTo: string | null = null;
  if (replyToDiscordMsgId) {
    const parent = await env.DB
      .prepare("SELECT id FROM messages WHERE agent_id = ? AND channel = 'discord' AND json_extract(metadata, '$.discord_message_id') = ? LIMIT 1")
      .bind(agentRow.agent_id, replyToDiscordMsgId)
      .first<{ id: string }>();
    if (parent) replyTo = parent.id;
  }
  // Fallback: auto-link to most recent pending blocking message
  if (!replyTo && !replyToDiscordMsgId) {
    const pending = await env.DB
      .prepare("SELECT id FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND mode = 'blocking' AND channel = 'discord' AND status IN ('sent', 'delivered') ORDER BY created_at DESC LIMIT 1")
      .bind(agentRow.agent_id)
      .first<{ id: string }>();
    if (pending) replyTo = pending.id;
  }
  // Scope thread-bound messages to their session. The unread/SSE filters route
  // boss_to_agent purely on target_session_id (session_id only affects the
  // browse view), so a thread message with target_session_id NULL would fan out
  // to every sibling session under this agent — the same mis-route this change
  // closes elsewhere. A non-thread channel message keeps sessionId NULL and
  // stays agent-wide. Mirrors the Telegram fresh-message path (webhooks.ts).
  const inserted = await insertMessageWithEvent(
    env,
    'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, reply_to, idempotency_key, metadata, session_id, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
    [createMessageId(), agentRow.agent_id, 'boss_to_agent', 'async', 'discord', text, 'sent', 'normal', replyTo, idempotencyKey ?? null, JSON.stringify(metadata), sessionId, sessionId],
    sessionId,
  );
  return inserted ?? null;
}
