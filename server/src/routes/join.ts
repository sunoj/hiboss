// Join route for device onboarding via pending approval or first-key bootstrap.
// Exports POST /api/join and GET /api/join/status without auth.
// Depends on Hono, D1, auth hashing, audit logging, and channel senders.

import { Hono } from 'hono';
import type { DiscordChannelConfig, Env, TelegramChannelConfig } from '../types';
import { logAudit } from '../audit';
import { sendDiscordMessage } from '../channels/discord';
import { sendTelegramMessage } from '../channels/telegram';
import { hashApiKey } from '../middleware/auth';

type JoinCreateResponse =
  | { request_id: string; poll_token: string; status: 'pending' }
  | { request_id: string; poll_token: string; status: 'approved'; key: string; agent_id: string };

type JoinStatusRow = {
  id: string;
  name: string;
  status: 'pending' | 'approved' | 'rejected';
  api_key: string | null;
  api_key_id: string | null;
};

type ChannelConfigRow = {
  channel: 'telegram' | 'discord';
  config: string;
};

const router = new Hono<{ Bindings: Env }>({});

router.post('/', async (c) => {
  const payload = await c.req.json<{ name?: string }>().catch((): { name?: string } => ({}));
  const name = payload.name?.trim() || 'new-agent';
  const pollToken = `jt_${generateHex(16)}`;
  const countRow = await c.env.DB.prepare('SELECT COUNT(*) AS cnt FROM api_keys').first<{ cnt: number }>();
  const count = Number(countRow?.cnt ?? 0);
  if (count === 0) {
    const key = `hb_${generateHex(16)}`;
    const keyHash = await hashApiKey(key);
    const apiKey = await c.env.DB
      .prepare('INSERT INTO api_keys (name, key_hash) VALUES (?, ?) RETURNING id')
      .bind(name, keyHash)
      .first<{ id: string }>();
    if (!apiKey) {
      return c.text('failed to create api key', 500);
    }
    const joinRequest = await c.env.DB
      .prepare('INSERT INTO join_requests (name, poll_token, status, api_key_id, api_key) VALUES (?, ?, ?, ?, ?) RETURNING id')
      .bind(name, pollToken, 'approved', apiKey.id, key)
      .first<{ id: string }>();
    if (!joinRequest) {
      await c.env.DB.prepare('DELETE FROM api_keys WHERE id = ?').bind(apiKey.id).run();
      return c.text('failed to create join request', 500);
    }
    c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'api_key.create', 'api_key', apiKey.id, 'join-auto-approve'));
    c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'join_request.approve', 'join_request', joinRequest.id, name));
    const response: JoinCreateResponse = {
      request_id: joinRequest.id,
      poll_token: pollToken,
      status: 'approved',
      key,
      agent_id: apiKey.id,
    };
    return c.json(response, 201);
  }
  const joinRequest = await c.env.DB
    .prepare('INSERT INTO join_requests (name, poll_token, status) VALUES (?, ?, ?) RETURNING id')
    .bind(name, pollToken, 'pending')
    .first<{ id: string }>();
  if (!joinRequest) {
    return c.text('failed to create join request', 500);
  }
  c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'join_request.create', 'join_request', joinRequest.id, name));
  c.executionCtx.waitUntil(notifyJoinRequest(c.env, joinRequest.id, name));
  const response: JoinCreateResponse = { request_id: joinRequest.id, poll_token: pollToken, status: 'pending' };
  return c.json(response, 201);
});

router.get('/status', async (c) => {
  const token = c.req.query('token');
  if (!token) {
    return c.text('missing token', 400);
  }
  const joinRequest = await c.env.DB
    .prepare('SELECT id, name, status, api_key, api_key_id FROM join_requests WHERE poll_token = ?')
    .bind(token)
    .first<JoinStatusRow>();
  if (!joinRequest) {
    return c.text('not found', 404);
  }
  const response: Record<string, string> = {
    status: joinRequest.status,
    name: joinRequest.name,
    request_id: joinRequest.id,
  };
  if (joinRequest.status === 'approved' && joinRequest.api_key && joinRequest.api_key_id) {
    response.key = joinRequest.api_key;
    response.agent_id = joinRequest.api_key_id;
    await c.env.DB
      .prepare("UPDATE join_requests SET api_key = NULL, updated_at = datetime('now') WHERE id = ?")
      .bind(joinRequest.id)
      .run();
    c.executionCtx.waitUntil(logAudit(c.env, 'system', 'join', 'join_request.key_delivered', 'join_request', joinRequest.id, joinRequest.name));
  }
  return c.json(response);
});

export const joinRouter = router;

async function notifyJoinRequest(env: Env, requestId: string, name: string): Promise<void> {
  const configs = await env.DB
    .prepare("SELECT DISTINCT channel, config FROM channel_configs WHERE enabled = 1 AND channel IN ('telegram', 'discord')")
    .all<ChannelConfigRow>();
  const sent = new Set<string>();
  const rows = configs.results ?? [];
  for (const row of rows) {
    try {
      const dedupeKey = getChannelDedupeKey(row);
      if (!dedupeKey || sent.has(dedupeKey)) {
        continue;
      }
      sent.add(dedupeKey);
      if (row.channel === 'telegram') {
        await sendTelegramMessage(getTelegramConfig(row.config), formatJoinMessage(name), {
          inlineKeyboard: [[
            { text: '✅ Approve', callback_data: `join:approve:${requestId}` },
            { text: '❌ Reject', callback_data: `join:reject:${requestId}` },
          ]],
        });
        continue;
      }
      await sendDiscordMessage(getDiscordConfig(row.config), formatJoinMessage(name), {
        components: [{
          type: 1,
          components: [
            { type: 2, style: 3, label: 'Approve', custom_id: `join:approve:${requestId}` },
            { type: 2, style: 4, label: 'Reject', custom_id: `join:reject:${requestId}` },
          ],
        }],
      });
    } catch {
      // Notification failures must never fail the join request.
    }
  }
}

function getChannelDedupeKey(row: ChannelConfigRow): string | null {
  try {
    const config = JSON.parse(row.config) as Record<string, unknown>;
    const target = row.channel === 'telegram' ? config['chat_id'] : config['channel_id'];
    return typeof target === 'string' && target ? `${row.channel}:${target}` : null;
  } catch {
    return null;
  }
}

function getTelegramConfig(raw: string): TelegramChannelConfig {
  const config = JSON.parse(raw) as Record<string, unknown>;
  if (typeof config['chat_id'] !== 'string' || typeof config['bot_token'] !== 'string') {
    throw new Error('telegram config malformed');
  }
  const telegramConfig: TelegramChannelConfig = { chat_id: config['chat_id'], bot_token: config['bot_token'] };
  if (typeof config['message_thread_id'] === 'number') {
    telegramConfig.message_thread_id = config['message_thread_id'];
  }
  return telegramConfig;
}

function getDiscordConfig(raw: string): DiscordChannelConfig {
  const config = JSON.parse(raw) as Record<string, unknown>;
  if (typeof config['webhook_url'] === 'string') {
    return {
      webhook_url: config['webhook_url'],
      avatar_url: typeof config['avatar_url'] === 'string' ? config['avatar_url'] : undefined,
      bot_token: typeof config['bot_token'] === 'string' ? config['bot_token'] : undefined,
      channel_id: typeof config['channel_id'] === 'string' ? config['channel_id'] : undefined,
    };
  }
  if (typeof config['bot_token'] !== 'string' || typeof config['channel_id'] !== 'string') {
    throw new Error('discord config malformed');
  }
  return { bot_token: config['bot_token'], channel_id: config['channel_id'] };
}

function formatJoinMessage(name: string): string {
  return `Join request for ${name}`;
}

function generateHex(bytes: number): string {
  const buf = new Uint8Array(bytes);
  crypto.getRandomValues(buf);
  return Array.from(buf)
    .map((value) => value.toString(16).padStart(2, '0'))
    .join('');
}
