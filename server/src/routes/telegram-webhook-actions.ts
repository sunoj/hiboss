// Telegram webhook helpers for callback queries, join actions, and reactions.
// Exports Telegram webhook action handlers used by the main webhook router.
// Depends on webhook helpers, audit logging, and Telegram channel API helpers.

import type { Context } from 'hono';
import { answerCallbackQuery, editMessageReplyMarkup } from '../channels/telegram';
import { logAudit } from '../audit';
import { hashApiKey } from '../middleware/auth';
import { notifyAgentCallback } from '../notify';
import type { Env, MessageRow } from '../types';
import { asString, findMessageByIdempotencyKey, hasBossAccess, mapMessage, resolveBossForChannel } from './webhook-helpers';

type TelegramConfigRow = { agent_id: string; config: string };
type TelegramContext = Context<{ Bindings: Env }>;

export async function handleTelegramCallbackQuery(c: TelegramContext, query: Record<string, unknown>): Promise<Response> {
  const data = asString(query['data']);
  const queryId = asString(query['id']);
  const chatMsg = query['message'] as Record<string, unknown> | undefined;
  const chatId = asString((chatMsg?.['chat'] as Record<string, unknown> | undefined)?.['id']);
  if (!data || !chatId) return c.text('invalid callback', 400);

  const configRow = await findTelegramConfigRow(c.env, chatId);
  const botToken = readBotToken(configRow?.config);
  const answer = (text: string) => answerTelegramCallback(c, botToken, queryId, text);
  if (!configRow) {
    answer('Error');
    return c.text('forbidden', 403);
  }
  if (data.startsWith('join:')) return handleJoinCallback(c, query, data, chatId, botToken, queryId);

  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(c.env, 'telegram', asString((query['from'] as Record<string, unknown>)?.['id']), true);
  if (bossError) {
    answer(bossError);
    return c.text(bossError, 403);
  }
  if (bossInfo && !(await hasBossAccess(c.env, bossInfo.id, configRow.agent_id, bossInfo.role))) {
    answer('No access');
    return c.text('no access to this agent', 403);
  }
  return handleMessageCallback(c, query, data, configRow, bossInfo, botToken, queryId);
}

export async function handleTelegramReaction(c: TelegramContext, reaction: Record<string, unknown>): Promise<Response> {
  const chatId = asString((reaction['chat'] as Record<string, unknown> | undefined)?.['id']);
  const tgMsgId = typeof reaction['message_id'] === 'number' ? reaction['message_id'] : undefined;
  if (!chatId || !tgMsgId) return c.text('invalid reaction', 400);
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(c.env, 'telegram', asString((reaction['user'] as Record<string, unknown>)?.['id']), true);
  if (bossError) return c.text(bossError, 403);
  const configRow = await c.env.DB
    .prepare("SELECT agent_id FROM channel_configs WHERE channel = 'telegram' AND enabled = 1 AND json_extract(config, '$.chat_id') = ?")
    .bind(chatId)
    .first<{ agent_id: string }>();
  if (!configRow) return c.text('forbidden', 403);
  if (bossInfo && !(await hasBossAccess(c.env, bossInfo.id, configRow.agent_id, bossInfo.role))) return c.text('no access to this agent', 403);
  const msg = await c.env.DB
    .prepare("SELECT id, metadata FROM messages WHERE agent_id = ? AND channel = 'telegram' AND json_extract(metadata, '$.telegram_message_id') = ? LIMIT 1")
    .bind(configRow.agent_id, tgMsgId)
    .first<{ id: string; metadata: string | null }>();
  if (!msg) return c.text('ok', 200);
  const emojis = ((reaction['new_reaction'] as { type: string; emoji?: string }[] | undefined) ?? [])
    .filter((value) => value.type === 'emoji' && value.emoji)
    .map((value) => value.emoji as string);
  const user = reaction['user'] as Record<string, unknown> | undefined;
  const userName = asString(user?.['first_name']) ?? asString(user?.['username']) ?? 'boss';
  const metadata = msg.metadata ? (JSON.parse(msg.metadata) as Record<string, unknown>) : {};
  metadata['reactions'] = emojis.map((emoji) => ({ emoji, user: userName }));
  await c.env.DB.prepare('UPDATE messages SET metadata = ? WHERE id = ?').bind(JSON.stringify(metadata), msg.id).run();
  return c.json({ ok: true });
}

async function handleMessageCallback(
  c: TelegramContext,
  query: Record<string, unknown>,
  data: string,
  configRow: TelegramConfigRow,
  bossInfo: { id: string; name: string; role: string } | null,
  botToken: string | undefined,
  queryId: string | undefined,
): Promise<Response> {
  const parsed = parseMessageCallbackData(data);
  if (!parsed) {
    answerTelegramCallback(c, botToken, queryId, 'Invalid');
    return c.text('invalid callback data', 400);
  }
  const parentMsg = await c.env.DB
    .prepare('SELECT id, metadata, status FROM messages WHERE id LIKE ? AND agent_id = ? LIMIT 1')
    .bind(`${parsed.msgPrefix}%`, configRow.agent_id)
    .first<{ id: string; metadata: string | null; status: string }>();
  if (!parentMsg) return replyWithAnswer(c, botToken, queryId, 'Not found', c.text('message not found', 404));
  if (parentMsg.status === 'expired') return replyWithAnswer(c, botToken, queryId, 'Options expired', c.text('options expired', 410));
  if (queryId) {
    const existing = await findMessageByIdempotencyKey(c.env, configRow.agent_id, queryId);
    if (existing) return replyWithAnswer(c, botToken, queryId, `Selected: ${existing.body}`, c.json(mapMessage(existing), 200));
  }
  const metadata = buildCallbackReplyMetadata(parentMsg.metadata, parsed.selectedOption, bossInfo);
  const inserted = await c.env.DB
    .prepare('INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, idempotency_key, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *')
    .bind(configRow.agent_id, 'boss_to_agent', 'async', 'telegram', parsed.selectedOption, 'sent', 'normal', parentMsg.id, queryId ?? null, metadata ? JSON.stringify(metadata) : null)
    .first<MessageRow>();
  if (!inserted) return replyWithAnswer(c, botToken, queryId, 'Error', c.text('failed to persist', 500));
  answerTelegramCallback(c, botToken, queryId, `Selected: ${parsed.selectedOption}`);
  await updateCallbackMessage(botToken, chatMessage(query), parsed.selectedOption);
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, configRow.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, bossInfo ? 'boss' : 'system', bossInfo?.id ?? 'telegram', 'message.callback', 'message', parentMsg.id, parsed.selectedOption));
  return c.json(mapMessage(inserted), 201);
}

async function handleJoinCallback(
  c: TelegramContext,
  query: Record<string, unknown>,
  data: string,
  chatId: string,
  botToken: string | undefined,
  queryId: string | undefined,
): Promise<Response> {
  const answer = (text: string) => answerTelegramCallback(c, botToken, queryId, text);
  if (!botToken) return replyWithAnswer(c, botToken, queryId, 'Error', c.text('forbidden', 403));
  const { boss: bossInfo, error: bossError } = await resolveBossForChannel(c.env, 'telegram', asString((query['from'] as Record<string, unknown>)?.['id']), true);
  if (bossError) return replyWithAnswer(c, botToken, queryId, bossError, c.text(bossError, 403));
  const parsed = parseJoinCallbackData(data);
  if (!parsed) return replyWithAnswer(c, botToken, queryId, 'Invalid', c.text('invalid callback data', 400));
  const result = parsed.action === 'approve' ? await approveJoinRequest(c.env, parsed.requestId) : await rejectJoinRequest(c.env, parsed.requestId);
  if (result.error) return replyWithAnswer(c, botToken, queryId, result.answerText, c.text(result.error, result.statusCode));
  answer(result.answerText);
  const chatMsg = chatMessage(query);
  if (chatMsg?.message_id) {
    const text = `${(chatMsg.text as string) ?? ''}\n\n${result.messageText}`;
    c.executionCtx.waitUntil(editMessageReplyMarkup(botToken, chatId, chatMsg.message_id, text));
  }
  c.executionCtx.waitUntil(logAudit(c.env, bossInfo ? 'boss' : 'system', bossInfo?.id ?? 'telegram', result.auditAction, 'join_request', parsed.requestId, result.auditDetails));
  if (result.apiKeyId) c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'api_key.create', 'api_key', result.apiKeyId, 'join-approve'));
  return c.json({ status: result.joinStatus });
}

async function updateCallbackMessage(
  botToken: string | undefined,
  message: { message_id?: number; text?: unknown; chat?: Record<string, unknown> } | undefined,
  selectedOption: string,
): Promise<void> {
  const chatId = asString(message?.chat?.['id']);
  const messageId = message?.message_id;
  if (botToken && chatId && messageId) {
    await editMessageReplyMarkup(botToken, chatId, messageId, `${(message.text as string) ?? ''}\n\n✅ Selected: ${selectedOption}`);
  }
}

function buildCallbackReplyMetadata(
  metadata: string | null,
  selectedOption: string,
  bossInfo: { id: string; name: string; role: string } | null,
): Record<string, unknown> | null {
  let replyMetadata: Record<string, unknown> | null = null;
  if (metadata) {
    try {
      const parentMeta = JSON.parse(metadata) as Record<string, unknown>;
      const actions = parentMeta['actions'] as Record<string, string> | undefined;
      if (actions?.[selectedOption]) replyMetadata = { action: actions[selectedOption] };
    } catch {}
  }
  return bossInfo ? { ...(replyMetadata ?? {}), boss_id: bossInfo.id, boss_name: bossInfo.name } : replyMetadata;
}

async function findTelegramConfigRow(env: Env, chatId: string): Promise<TelegramConfigRow | null> {
  return env.DB
    .prepare("SELECT agent_id, config FROM channel_configs WHERE channel = 'telegram' AND enabled = 1 AND json_extract(config, '$.chat_id') = ?")
    .bind(chatId)
    .first<TelegramConfigRow>();
}

function readBotToken(config: string | undefined): string | undefined {
  if (!config) return undefined;
  try {
    const parsed = JSON.parse(config) as Record<string, unknown>;
    return typeof parsed['bot_token'] === 'string' ? parsed['bot_token'] : undefined;
  } catch {
    return undefined;
  }
}

function answerTelegramCallback(c: TelegramContext, botToken: string | undefined, queryId: string | undefined, text: string): void {
  if (botToken && queryId) c.executionCtx.waitUntil(answerCallbackQuery(botToken, queryId, text));
}

function replyWithAnswer(c: TelegramContext, botToken: string | undefined, queryId: string | undefined, text: string, response: Response): Response {
  answerTelegramCallback(c, botToken, queryId, text);
  return response;
}

function chatMessage(query: Record<string, unknown>): { message_id?: number; text?: unknown; chat?: Record<string, unknown> } | undefined {
  return query['message'] as { message_id?: number; text?: unknown; chat?: Record<string, unknown> } | undefined;
}

function parseMessageCallbackData(data: string): { msgPrefix: string; selectedOption: string } | null {
  const colonIdx = data.indexOf(':');
  if (colonIdx < 1) return null;
  const msgPrefix = data.slice(0, colonIdx);
  if (!/^[0-9a-f]{8,}$/i.test(msgPrefix)) return null;
  return { msgPrefix, selectedOption: data.slice(colonIdx + 1) };
}

type JoinCallbackAction = 'approve' | 'reject';
type JoinCallbackResult = {
  answerText: string;
  auditAction: string;
  auditDetails: string;
  joinStatus: 'approved' | 'rejected';
  messageText: string;
  statusCode: 200 | 404 | 409;
  error?: string;
  apiKeyId?: string;
};

function parseJoinCallbackData(data: string): { action: JoinCallbackAction; requestId: string } | null {
  const match = /^join:(approve|reject):([0-9a-f]{32})$/i.exec(data);
  return match ? { action: match[1].toLowerCase() as JoinCallbackAction, requestId: match[2].toLowerCase() } : null;
}

async function approveJoinRequest(env: Env, requestId: string): Promise<JoinCallbackResult> {
  const joinRequest = await env.DB.prepare("SELECT id, name, status FROM join_requests WHERE id = ?").bind(requestId).first<{ id: string; name: string; status: string }>();
  if (!joinRequest) return joinErrorResult('Not found', 'join request not found', 404);
  if (joinRequest.status !== 'pending') return joinErrorResult(`Already ${joinRequest.status}`, `join request already ${joinRequest.status}`, 409);
  const key = `hb_${generateHex(16)}`;
  const keyHash = await hashApiKey(key);
  const apiKey = await env.DB.prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id').bind(joinRequest.name, keyHash).first<{ id: string }>();
  if (!apiKey) return joinErrorResult('Error', 'failed to create api key', 409);
  const update = await env.DB
    .prepare("UPDATE join_requests SET status = 'approved', api_key_id = ?, api_key = ?, updated_at = datetime('now') WHERE id = ? AND status = 'pending'")
    .bind(apiKey.id, key, requestId)
    .run();
  if (!update.meta.changes) {
    await env.DB.prepare('DELETE FROM api_keys WHERE id = ?').bind(apiKey.id).run();
    return joinErrorResult('Already handled', 'join request no longer pending', 409);
  }
  return { answerText: '✅ Approved', auditAction: 'join_request.approve', auditDetails: joinRequest.name, joinStatus: 'approved', messageText: '✅ Approved', statusCode: 200, apiKeyId: apiKey.id };
}

async function rejectJoinRequest(env: Env, requestId: string): Promise<JoinCallbackResult> {
  const joinRequest = await env.DB.prepare("SELECT name, status FROM join_requests WHERE id = ?").bind(requestId).first<{ name: string; status: string }>();
  if (!joinRequest) return joinErrorResult('Not found', 'join request not found', 404);
  if (joinRequest.status !== 'pending') return joinErrorResult(`Already ${joinRequest.status}`, `join request already ${joinRequest.status}`, 409);
  const update = await env.DB
    .prepare("UPDATE join_requests SET status = 'rejected', updated_at = datetime('now') WHERE id = ? AND status = 'pending'")
    .bind(requestId)
    .run();
  if (!update.meta.changes) return joinErrorResult('Already handled', 'join request no longer pending', 409);
  return { answerText: '❌ Rejected', auditAction: 'join_request.reject', auditDetails: joinRequest.name, joinStatus: 'rejected', messageText: '❌ Rejected', statusCode: 200 };
}

function joinErrorResult(answerText: string, error: string, statusCode: 404 | 409): JoinCallbackResult {
  return { answerText, auditAction: 'join_request.error', auditDetails: error, joinStatus: 'rejected', messageText: answerText, statusCode, error };
}

function generateHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf).map((value) => value.toString(16).padStart(2, '0')).join('');
}
