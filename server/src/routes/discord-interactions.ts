// Discord interaction webhook for slash commands and buttons.
// Exports the discordInteractionsRouter with signature verification and routing.
// Depends on Hono, Web Crypto, and shared types/notify helpers.

import { Hono, Context } from 'hono';
import type { Env, MessageRow } from '../types';
import { notifyAgentCallback } from '../notify';
import { logAudit } from '../audit';
import { apiAuth } from '../middleware/auth';

interface DiscordInteractionPayload {
  type: number;
  data?: DiscordInteractionData;
  channel_id?: string;
  member?: { user?: { id?: string } };
  message?: { content?: string };
}

interface DiscordInteractionData {
  name?: string;
  options?: DiscordInteractionOption[];
  custom_id?: string;
}

type DiscordInteractionOption = {
  name: string;
  value?: unknown;
};

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
  if (!message) {
    return c.text('message option required', 400);
  }
  const agentRow = await findDiscordAgent(c.env, channelId);
  if (!agentRow) {
    return c.json({ type: 4, data: { content: 'No agent configured for this channel.', flags: 64 } });
  }
  const discordUserId = payload.member?.user?.id;
  const bossCheck = await checkBossPermission(c.env, 'discord', discordUserId ? String(discordUserId) : undefined, agentRow.agent_id, false);
  if (bossCheck.error) {
    return c.json({ type: 4, data: { content: bossCheck.error, flags: 64 } });
  }
  const meta = bossCheck.boss ? { ...payload as Record<string, unknown>, boss_id: bossCheck.boss.id, boss_name: bossCheck.boss.name } : payload;
  // Auto-link to most recent pending blocking message for this agent
  let replyTo: string | null = null;
  const pendingMsg = await c.env.DB
    .prepare(
      "SELECT id FROM messages WHERE agent_id = ? AND direction = 'agent_to_boss' AND mode = 'blocking' AND channel = 'discord' AND status IN ('sent', 'delivered') ORDER BY created_at DESC LIMIT 1"
    )
    .bind(agentRow.agent_id)
    .first<{ id: string }>();
  if (pendingMsg) replyTo = pendingMsg.id;
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(agentRow.agent_id, 'boss_to_agent', 'async', 'discord', message, 'sent', 'normal', replyTo, JSON.stringify(meta))
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
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
  const colonIndex = customId.indexOf(':');
  if (colonIndex < 1) {
    return c.text('invalid custom_id format', 400);
  }
  const msgPrefix = customId.slice(0, colonIndex);
  const selectedOption = customId.slice(colonIndex + 1);
  if (!selectedOption) {
    return c.text('invalid selection', 400);
  }
  if (!/^[0-9a-f]{8,}$/i.test(msgPrefix)) {
    return c.text('invalid message prefix', 400);
  }
  const agentRow = await findDiscordAgent(c.env, channelId);
  if (!agentRow) {
    return c.json({ type: 4, data: { content: 'No agent configured for this channel.', flags: 64 } });
  }
  const btnUserId = payload.member?.user?.id;
  const btnBossCheck = await checkBossPermission(c.env, 'discord', btnUserId ? String(btnUserId) : undefined, agentRow.agent_id, true);
  if (btnBossCheck.error) {
    return c.json({ type: 4, data: { content: btnBossCheck.error, flags: 64 } });
  }
  const parentMsg = await c.env.DB
    .prepare('SELECT id, metadata, status FROM messages WHERE id LIKE ? AND agent_id = ? LIMIT 1')
    .bind(`${msgPrefix}%`, agentRow.agent_id)
    .first<{ id: string; metadata: string | null; status: string }>();
  if (!parentMsg) {
    return c.text('message not found', 404);
  }
  if (parentMsg.status === 'expired') {
    return c.json({ type: 4, data: { content: '⏰ Options expired', flags: 64 } });
  }
  const replyMetadata = getActionMetadata(parentMsg.metadata, selectedOption);
  const inserted = await c.env.DB
    .prepare(
      'INSERT INTO messages (agent_id, direction, mode, channel, body, status, priority, reply_to, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *'
    )
    .bind(
      agentRow.agent_id,
      'boss_to_agent',
      'async',
      'discord',
      selectedOption,
      'sent',
      'normal',
      parentMsg.id,
      replyMetadata
    )
    .first<MessageRow>();
  if (!inserted) {
    return c.text('failed to persist', 500);
  }
  c.executionCtx.waitUntil(notifyAgentCallback(c.env, agentRow.agent_id, inserted));
  c.executionCtx.waitUntil(logAudit(c.env, btnBossCheck.boss ? 'boss' : 'system', btnBossCheck.boss?.id ?? 'discord', 'message.callback', 'message', parentMsg.id, selectedOption));
  // Type 7 = UPDATE_MESSAGE: replaces the original message and removes buttons
  const originalContent = payload.message?.content ?? '';
  return c.json({ type: 7, data: { content: `${originalContent}\n\n✅ Selected: ${selectedOption}`, components: [] } });
}

async function findDiscordAgent(env: Env, channelId: string): Promise<{ agent_id: string } | null> {
  return env.DB
    .prepare(
      "SELECT agent_id FROM channel_configs WHERE channel = 'discord' AND json_extract(config, '$.channel_id') = ?"
    )
    .bind(channelId)
    .first<{ agent_id: string }>();
}

function getActionMetadata(metadata: string | null, selectedOption: string): string | null {
  if (!metadata) {
    return null;
  }
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    const actions = parsed['actions'] as Record<string, string> | undefined;
    if (actions && typeof actions === 'object' && actions[selectedOption]) {
      return JSON.stringify({ action: actions[selectedOption] });
    }
  } catch {
    // ignore malformed metadata
  }
  return null;
}

function asString(value: unknown): string | undefined {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return value.toString();
  }
  return undefined;
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
  const publicKeyBytes = hexToUint8Array(publicKey);
  const signatureBytes = hexToUint8Array(signature);
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

function hexToUint8Array(hex: string): Uint8Array {
  const normalized = hex.startsWith('0x') ? hex.slice(2) : hex;
  const evened = normalized.length % 2 === 0 ? normalized : `0${normalized}`;
  const array = new Uint8Array(evened.length / 2);
  for (let i = 0; i < evened.length; i += 2) {
    array[i / 2] = parseInt(evened.slice(i, i + 2), 16);
  }
  return array;
}

async function checkBossPermission(
  env: Env,
  channel: 'discord' | 'telegram',
  userId: string | undefined,
  agentId: string,
  allowViewer: boolean
): Promise<{ boss: { id: string; name: string; role: string } | null; error?: string }> {
  const countRow = await env.DB.prepare('SELECT COUNT(*) AS total FROM bosses').first<{ total: number }>();
  if ((countRow?.total ?? 0) === 0) return { boss: null };
  if (!userId) return { boss: null, error: 'Unknown sender' };
  const col = channel === 'telegram' ? 'telegram_user_id' : 'discord_user_id';
  const boss = await env.DB.prepare(`SELECT id, name, role FROM bosses WHERE ${col} = ? LIMIT 1`).bind(userId).first<{ id: string; name: string; role: string }>();
  if (!boss) return { boss: null, error: 'Unknown sender' };
  if (!allowViewer && boss.role === 'viewer') return { boss: null, error: 'Viewer cannot send messages' };
  if (boss.role !== 'admin') {
    const access = await env.DB.prepare('SELECT 1 AS ok FROM boss_agent_access WHERE boss_id = ? AND agent_id = ? LIMIT 1').bind(boss.id, agentId).first<{ ok: number }>();
    if (!access) return { boss: null, error: 'No access to this agent' };
  }
  return { boss };
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
  const response = await fetch(
    `https://discord.com/api/v10/applications/${encodeURIComponent(payload.app_id)}/commands`,
    {
      method: 'POST',
      headers: { Authorization: `Bot ${payload.bot_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(command),
    }
  );
  if (!response.ok) {
    const body = await response.text();
    return c.text(body, 502);
  }
  return c.json(await response.json(), 201);
});

export const discordInteractionsRouter = router;
