// Discord interaction webhook for slash commands and buttons.
// Exports the discordInteractionsRouter with signature verification and routing.
// Depends on Hono, Web Crypto, and shared types/notify helpers.

import { Hono, Context } from 'hono';
import type { Env, MessageRow } from '../types';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { apiAuth } from '../middleware/auth';
import { handleDiscordOptionCallback } from './discord-option-callback';
import { approveJoinRequest, parseJoinCallbackData, rejectJoinRequest } from './join-helpers';
import { asString, checkBossPermission, findDiscordAgent, resolveBossForChannel } from './webhook-helpers';
import { replyTargetSession } from './message-helpers';
import { createMessageId, insertMessageWithEvent } from '../session-events';

interface DiscordInteractionPayload { type: number; data?: DiscordInteractionData; channel_id?: string; member?: { user?: { id?: string } }; message?: { content?: string } }
interface DiscordInteractionData { name?: string; options?: DiscordInteractionOption[]; custom_id?: string }
type DiscordInteractionOption = { name: string; value?: unknown };

const router = new Hono<{ Bindings: Env }>({});

router.post('/', async (c) => {
  const timestamp = c.req.header('X-Signature-Timestamp');
  const signature = c.req.header('X-Signature-Ed25519');
  if (!timestamp || !signature) {
    return c.text('missing signature headers', 401);
  }
  const publicKey = c.env.DISCORD_PUBLIC_KEY;
  if (!publicKey) {
    return c.text('public key unavailable', 500);
  }
  const body = await c.req.text();
  const verified = await verifyDiscordSignature(publicKey, signature, timestamp, body);
  if (!verified) {
    return c.text('invalid signature', 401);
  }
  const timestampSeconds = parseInt(timestamp ?? '0', 10);
  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - timestampSeconds) > 300) {
    return c.text('stale interaction', 401);
  }
  let payload: DiscordInteractionPayload;
  try {
    payload = JSON.parse(body) as DiscordInteractionPayload;
  } catch {
    return c.text('invalid payload', 400);
  }
  switch (payload.type) {
    case 1:
      return c.json({ type: 1 });
    case 2:
      return handleApplicationCommand(c, payload);
    case 3:
      return handleMessageComponent(c, payload);
    default:
      return c.text('unsupported interaction type', 400);
  }
});

async function handleApplicationCommand(
  c: Context<{ Bindings: Env }>,
  payload: DiscordInteractionPayload
): Promise<Response> {
  const channelId = asString(payload.channel_id);
  if (!channelId) {
    return c.text('missing channel_id', 400);
  }
  const commandName = payload.data?.name;
  if (commandName !== 'msg') {
    return c.text('unsupported command', 400);
  }
  const messageOption = payload.data?.options?.find((option) => option.name === 'message');
  const message = asString(messageOption?.value);
  if (!message) return c.text('message option required', 400);
  const agentRow = await findDiscordAgent(c.env, channelId);
  if (!agentRow) {
    return c.json({ type: 4, data: { content: 'No agent configured for this channel.', flags: 64 } });
  }
  const discordUserId = payload.member?.user?.id;
  const bossCheck = await checkBossPermission(c.env, 'discord', discordUserId ? String(discordUserId) : undefined, agentRow.agent_id, false);
  if (bossCheck.error) {
    return c.json({ type: 4, data: { content: bossCheck.error, flags: 64 } });
  }
  const meta = bossCheck.boss
    ? { ...(payload as unknown as Record<string, unknown>), boss_id: bossCheck.boss.id, boss_name: bossCheck.boss.name }
    : payload;
  // Auto-link to most recent pending blocking message for this agent
  let replyTo: string | null = null;
  const pendingMsg = await c.env.DB
    .prepare(
      "SELECT id, session_id, target_session_id FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND mode = 'blocking' AND channel = 'discord' AND status IN ('sent', 'delivered') ORDER BY created_at DESC LIMIT 1"
    )
    .bind(agentRow.agent_id)
    .first<Pick<MessageRow, 'id' | 'session_id' | 'target_session_id'>>();
  if (pendingMsg) replyTo = pendingMsg.id;
  const targetSessionId = pendingMsg ? replyTargetSession(pendingMsg) : null;
  const inserted = await insertMessageWithEvent(
    c.env,
    'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, reply_to, metadata, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
    [createMessageId(), agentRow.agent_id, 'boss_to_agent', 'async', 'discord', message, 'sent', 'normal', replyTo, JSON.stringify(meta), targetSessionId],
    targetSessionId,
  );
  if (!inserted) return c.text('failed to persist', 500);
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, agentRow.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, bossCheck.boss ? 'boss' : 'system', bossCheck.boss?.id ?? 'discord', 'message.send', 'message', inserted.id, 'discord-slash'));
  return c.json({ type: 4, data: { content: 'Message sent to agent.' } });
}

async function handleMessageComponent(
  c: Context<{ Bindings: Env }>,
  payload: DiscordInteractionPayload
): Promise<Response> {
  const channelId = asString(payload.channel_id);
  const customId = payload.data?.custom_id;
  if (!channelId || !customId) {
    return c.text('missing channel or custom_id', 400);
  }
  if (customId.startsWith('join:')) {
    return handleDiscordJoinCallback(c, payload, customId, channelId);
  }
  return handleDiscordOptionCallback(c, payload, customId, channelId);
}

async function handleDiscordJoinCallback(
  c: Context<{ Bindings: Env }>,
  payload: DiscordInteractionPayload,
  customId: string,
  channelId: string
): Promise<Response> {
  if (!(await findDiscordAgent(c.env, channelId))) {
    return c.json({ type: 4, data: { content: 'No agent configured for this channel.', flags: 64 } });
  }
  const { boss, error } = await resolveBossForChannel(c.env, 'discord', payload.member?.user?.id, true);
  if (error) {
    return c.json({ type: 4, data: { content: formatBossLookupError(error), flags: 64 } });
  }
  const parsed = parseJoinCallbackData(customId);
  if (!parsed) {
    return c.text('invalid callback data', 400);
  }
  if (parsed.action === 'approve' && boss && boss.role !== 'admin') {
    return c.text('admin required', 403);
  }
  const result = parsed.action === 'approve' ? await approveJoinRequest(c.env, parsed.requestId) : await rejectJoinRequest(c.env, parsed.requestId);
  if (!result.error) {
    c.executionCtx.waitUntil(logAudit(c.env, boss ? 'boss' : 'system', boss?.id ?? 'discord', result.auditAction, 'join_request', parsed.requestId, result.auditDetails));
    if (result.apiKeyId) c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'api_key.create', 'api_key', result.apiKeyId, 'join-approve'));
  }
  return c.json({ type: 7, data: { content: formatUpdatedMessage(payload.message?.content, result.messageText), components: [] } });
}

async function verifyDiscordSignature(
  publicKey: string,
  signature: string,
  timestamp: string,
  body: string
): Promise<boolean> {
  const subtle = globalThis.crypto?.subtle;
  if (!subtle) {
    return false;
  }
  const publicKeyBytes = hexToArrayBuffer(publicKey);
  const signatureBytes = hexToArrayBuffer(signature);
  const payload = new TextEncoder().encode(timestamp + body);
  const algorithms = ['Ed25519', 'NODE-ED25519'] as const;
  for (const name of algorithms) {
    try {
      const key = await subtle.importKey('raw', publicKeyBytes, { name }, false, ['verify']);
      if (await subtle.verify({ name }, key, signatureBytes, payload)) {
        return true;
      }
    } catch {
      continue;
    }
  }
  return false;
}

function hexToArrayBuffer(hex: string): ArrayBuffer {
  const normalized = hex.startsWith('0x') ? hex.slice(2) : hex;
  const evened = normalized.length % 2 === 0 ? normalized : `0${normalized}`;
  const array = new Uint8Array(evened.length / 2);
  for (let i = 0; i < evened.length; i += 2) {
    array[i / 2] = parseInt(evened.slice(i, i + 2), 16);
  }
  return array.buffer.slice(0);
}

function formatUpdatedMessage(originalContent: string | undefined, resultText: string): string {
  return originalContent ? `${originalContent}\n\n${resultText}` : resultText;
}

function formatBossLookupError(error: string): string {
  return error === 'viewer cannot send messages' ? 'Viewer cannot send messages' : 'Unknown sender';
}

router.post('/register-commands', apiAuth, async (c) => {
  const payload = await c.req.json<{ app_id?: string; bot_token?: string }>();
  if (!payload.app_id || !payload.bot_token) {
    return c.text('app_id and bot_token required', 400);
  }
  const command = {
    name: 'msg',
    type: 1,
    description: 'Send a message to the AI agent monitoring this channel',
    options: [{ name: 'message', description: 'The message to send', type: 3, required: true }],
  };
  const response = await fetch(`https://discord.com/api/v10/applications/${encodeURIComponent(payload.app_id)}/commands`, {
    method: 'POST',
    headers: { Authorization: `Bot ${payload.bot_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(command),
  });
  if (!response.ok) {
    const body = await response.text();
    return c.text(body, 502);
  }
  return c.json(await response.json(), 201);
});

export const discordInteractionsRouter = router;
