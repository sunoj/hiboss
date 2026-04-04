// End-to-end tests for join request creation, approval, rejection, and bootstrap flows.
// Covers Telegram and Discord approval callbacks plus poll-token status delivery.
// Depends on cloudflare:test, D1 fixtures, webhook secrets, and signed Discord payloads.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const JOIN_BASE = 'https://test.local/api/join';
const TELEGRAM_SECRET = 'join-flow-telegram-secret';
const DISCORD_CHANNEL_ID = 'join-flow-discord-channel';
const TELEGRAM_CHAT_ID = 'join-flow-telegram-chat';
const TEXT_ENCODER = new TextEncoder();

let discordPrivateKey: CryptoKey;

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS join_requests (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL, poll_token TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')), api_key_id TEXT REFERENCES api_keys(id), api_key TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')))"
  ).run();
  env.TELEGRAM_WEBHOOK_SECRET = TELEGRAM_SECRET;
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?), (?, ?, ?)'
  )
    .bind(
      getTestAgentId(),
      'telegram',
      JSON.stringify({ chat_id: TELEGRAM_CHAT_ID, bot_token: 'join-flow-bot' }),
      getTestAgentId(),
      'discord',
      JSON.stringify({ channel_id: DISCORD_CHANNEL_ID, bot_token: 'join-flow-token' }),
    )
    .run();
  const keyPair = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  discordPrivateKey = keyPair.privateKey;
  const publicKeyBytes = await crypto.subtle.exportKey('raw', keyPair.publicKey);
  env.DISCORD_PUBLIC_KEY = bufferToHex(publicKeyBytes);
});

afterEach(async () => {
  await env.DB.prepare("DELETE FROM join_requests WHERE name LIKE 'join-flow-%'").run();
  await env.DB.prepare("DELETE FROM bosses WHERE name LIKE 'join-flow-%'").run();
  await env.DB.prepare("DELETE FROM api_keys WHERE name LIKE 'join-flow-%'").run();
});

describe('Join flow', () => {
  it('creates a pending join request through POST /api/join', async () => {
    const res = await createJoinRequest('join-flow-pending');

    expect(res.status).toBe('pending');
    const stored = await env.DB
      .prepare('SELECT status, poll_token FROM join_requests WHERE id = ?')
      .bind(res.request_id)
      .first<{ status: string; poll_token: string }>();
    expect(stored).toEqual({ status: 'pending', poll_token: res.poll_token });
  });

  it('approves a pending join request from a Telegram callback and returns the key via polling', async () => {
    await createBoss('join-flow-telegram-admin', 'telegram', '9001');
    const join = await createJoinRequest('join-flow-telegram-approve');

    const callbackRes = await postTelegramCallback(`join:approve:${join.request_id}`, '9001');
    expect(callbackRes.status).toBe(200);
    expect(await callbackRes.json()).toEqual({ status: 'approved' });

    const statusRes = await SELF.fetch(`${JOIN_BASE}/status?token=${join.poll_token}`);
    expect(statusRes.status).toBe(200);
    expect(await statusRes.json()).toMatchObject({
      status: 'approved',
      request_id: join.request_id,
      key: expect.stringMatching(/^hb_/),
      agent_id: expect.any(String),
    });
  });

  it('approves a pending join request from a Discord interaction callback', async () => {
    await createBoss('join-flow-discord-admin', 'discord', '777');
    const join = await createJoinRequest('join-flow-discord-approve');

    const res = await signedDiscordFetch({
      type: 3,
      channel_id: DISCORD_CHANNEL_ID,
      data: { custom_id: `join:approve:${join.request_id}` },
      member: { user: { id: '777' } },
      message: { content: 'Join request for join-flow-discord-approve' },
    });

    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({
      type: 7,
      data: { content: expect.stringContaining('✅ Approved'), components: [] },
    });

    const stored = await env.DB
      .prepare('SELECT status, api_key_id FROM join_requests WHERE id = ?')
      .bind(join.request_id)
      .first<{ status: string; api_key_id: string | null }>();
    expect(stored?.status).toBe('approved');
    expect(stored?.api_key_id).toBeTruthy();
  });

  it('rejects a join request through both Telegram and Discord callbacks', async () => {
    await createBoss('join-flow-telegram-rejector', 'telegram', '9002');
    await createBoss('join-flow-discord-rejector', 'discord', '778');
    const telegramJoin = await createJoinRequest('join-flow-telegram-reject');
    const discordJoin = await createJoinRequest('join-flow-discord-reject');

    const telegramRes = await postTelegramCallback(`join:reject:${telegramJoin.request_id}`, '9002');
    expect(telegramRes.status).toBe(200);
    expect(await telegramRes.json()).toEqual({ status: 'rejected' });

    const discordRes = await signedDiscordFetch({
      type: 3,
      channel_id: DISCORD_CHANNEL_ID,
      data: { custom_id: `join:reject:${discordJoin.request_id}` },
      member: { user: { id: '778' } },
      message: { content: 'Join request for join-flow-discord-reject' },
    });
    expect(discordRes.status).toBe(200);
    expect(await discordRes.json()).toMatchObject({
      type: 7,
      data: { content: expect.stringContaining('❌ Rejected'), components: [] },
    });

    const telegramStatus = await SELF.fetch(`${JOIN_BASE}/status?token=${telegramJoin.poll_token}`);
    expect(await telegramStatus.json()).toMatchObject({ status: 'rejected', request_id: telegramJoin.request_id });
    const discordRow = await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?').bind(discordJoin.request_id).first<{ status: string }>();
    expect(discordRow?.status).toBe('rejected');
  });

  it('rejects duplicate approvals after the request is already approved', async () => {
    await createBoss('join-flow-telegram-duplicate', 'telegram', '9003');
    const join = await createJoinRequest('join-flow-duplicate-approve');

    expect((await postTelegramCallback(`join:approve:${join.request_id}`, '9003')).status).toBe(200);

    const duplicateRes = await postTelegramCallback(`join:approve:${join.request_id}`, '9003');
    expect(duplicateRes.status).toBe(409);
    expect(await duplicateRes.text()).toBe('join request already approved');
  });

  it('auto-approves the first agent bootstrap request when no API keys exist', async () => {
    await env.DB.prepare('DELETE FROM channel_configs').run();
    await env.DB.prepare('DELETE FROM boss_agent_access').run();
    await env.DB.prepare('DELETE FROM api_keys').run();

    const res = await SELF.fetch(JOIN_BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'join-flow-bootstrap' }),
    });

    expect(res.status).toBe(201);
    expect(await res.json()).toMatchObject({
      status: 'approved',
      key: expect.stringMatching(/^hb_/),
      agent_id: expect.any(String),
    });

    await restoreDefaultAgent();
  });
});

async function createJoinRequest(name: string): Promise<{ request_id: string; poll_token: string; status: string }> {
  const res = await SELF.fetch(JOIN_BASE, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }),
  });
  expect(res.status).toBe(201);
  return res.json() as Promise<{ request_id: string; poll_token: string; status: string }>;
}

async function createBoss(name: string, channel: 'telegram' | 'discord', userId: string): Promise<void> {
  await env.DB.prepare(
    `INSERT OR REPLACE INTO bosses (id, name, role, ${channel === 'telegram' ? 'telegram_user_id' : 'discord_user_id'}) VALUES (?, ?, 'admin', ?)`
  ).bind(name, name, userId).run();
}

async function postTelegramCallback(data: string, userId: string): Promise<Response> {
  return SELF.fetch('https://test.local/api/webhooks/telegram', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Telegram-Bot-Api-Secret-Token': TELEGRAM_SECRET,
    },
    body: JSON.stringify({
      callback_query: {
        id: `cb-${userId}`,
        data,
        from: { id: userId },
        message: {
          message_id: 100,
          text: 'Join request',
          chat: { id: TELEGRAM_CHAT_ID },
        },
      },
    }),
  });
}

async function signedDiscordFetch(body: Record<string, unknown>, timestamp = String(Math.floor(Date.now() / 1000))): Promise<Response> {
  const payload = JSON.stringify(body);
  const signatureBuffer = await crypto.subtle.sign('Ed25519', discordPrivateKey, TEXT_ENCODER.encode(timestamp + payload));
  return SELF.fetch('https://test.local/api/webhooks/discord-interactions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Signature-Timestamp': timestamp,
      'X-Signature-Ed25519': bufferToHex(signatureBuffer),
    },
    body: payload,
  });
}

async function restoreDefaultAgent(): Promise<void> {
  const keyHash = await hashApiKey('hb_test_key_0000000000000000');
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(getTestAgentId(), 'test-agent', keyHash)
    .run();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?), (?, ?, ?)'
  )
    .bind(
      getTestAgentId(),
      'telegram',
      JSON.stringify({ chat_id: TELEGRAM_CHAT_ID, bot_token: 'join-flow-bot' }),
      getTestAgentId(),
      'discord',
      JSON.stringify({ channel_id: DISCORD_CHANNEL_ID, bot_token: 'join-flow-token' }),
    )
    .run();
}

function bufferToHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}
