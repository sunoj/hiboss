// Tests for the Discord interactions webhook.
// Exercises signed requests, button flows, and validation errors.
// Depends on cloudflare:test env, Ed25519 crypto, and shared helpers.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';

const BASE_URL = 'https://test.local/api/webhooks/discord-interactions';
const CHANNEL_ID = 'test-discord-ch';
const TEXT_ENCODER = new TextEncoder();

type BodyInput = string | Record<string, unknown>;

type HeaderMap = Record<string, string>;
type InteractionResponse = { type: number; data?: { content?: string; components?: unknown[]; flags?: number } };

const TEST_AGENT_ID = getTestAgentId();

let testPrivateKey: CryptoKey;

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS join_requests (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL, poll_token TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')), api_key_id TEXT REFERENCES api_keys(id), api_key TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')))"
  ).run();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(TEST_AGENT_ID, 'discord', JSON.stringify({ channel_id: CHANNEL_ID, bot_token: 'fake-token' }))
    .run();
  const keyPair = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  testPrivateKey = keyPair.privateKey;
  const publicKeyBytes = await crypto.subtle.exportKey('raw', keyPair.publicKey);
  env.DISCORD_PUBLIC_KEY = bufferToHex(publicKeyBytes);
});

describe('POST /api/webhooks/discord-interactions', () => {
  it('responds to PING interactions', async () => {
    const payload = { type: 1 };
    const res = await signedFetch(payload);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ type: 1 });
  });

  it('creates a boss_to_agent message for /msg commands', async () => {
    const bodyText = 'hello from discord';
    const payload = {
      type: 2,
      channel_id: CHANNEL_ID,
      data: {
        name: 'msg',
        options: [{ name: 'message', value: bodyText }],
      },
    };

    const res = await signedFetch(payload);
    expect(res.status).toBe(200);
    const responseBody = await res.json() as InteractionResponse;
    expect(responseBody.data?.content).toBe('Message sent to agent.');

    const stored = await env.DB
      .prepare(
        'SELECT body, agent_id, channel, metadata FROM messages WHERE body = ? AND channel = ? AND agent_id = ? ORDER BY created_at DESC LIMIT 1'
      )
      .bind(bodyText, 'discord', TEST_AGENT_ID)
      .first<{ body: string; agent_id: string; channel: string; metadata: string | null }>();

    expect(stored).not.toBeNull();
    expect(stored?.body).toBe(bodyText);
    expect(stored?.agent_id).toBe(TEST_AGENT_ID);
    expect(stored?.channel).toBe('discord');
    const metadata = stored?.metadata ? JSON.parse(stored.metadata) : null;
    expect(metadata?.type).toBe(2);
  });

  it('creates a reply when a button is clicked', async () => {
    const parentId = 'b077e0fa00000001aabbccdd00000001';
    await env.DB
      .prepare(
        "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at) VALUES (?, ?, 'agent_to_boss', 'blocking', 'discord', 'parent', 'delivered', 'normal', ?, ?)"
      )
      .bind(
        parentId,
        TEST_AGENT_ID,
        JSON.stringify({ options: ['optionA'] }),
        new Date(Date.now() + 60_000).toISOString(),
      )
      .run();

    const payload = {
      type: 3,
      channel_id: CHANNEL_ID,
      data: { custom_id: 'b077e0fa:optionA' },
      message: { content: 'Pick one:' },
    };

    const res = await signedFetch(payload);
    expect(res.status).toBe(200);
    const data = await res.json() as InteractionResponse;
    expect(data.type).toBe(7);
    expect(data.data?.content).toContain('Pick one:');
    expect(data.data?.content).toContain('✅ Selected: optionA');
    expect(data.data?.components).toEqual([]);

    const reply = await env.DB
      .prepare('SELECT body, reply_to FROM messages WHERE reply_to = ? ORDER BY created_at DESC LIMIT 1')
      .bind(parentId)
      .first<{ body: string; reply_to: string | null }>();

    expect(reply).not.toBeNull();
    expect(reply?.body).toBe('optionA');
    expect(reply?.reply_to).toBe(parentId);
    const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(parentId).first<{ status: string }>();
    expect(parent?.status).toBe('replied');
  });

  it('rejects a forged custom_id that is not one of the offered options', async () => {
    const parentId = 'b077e0fb00000001aabbccdd00000001';
    await env.DB
      .prepare(
        "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at) VALUES (?, ?, 'agent_to_boss', 'blocking', 'discord', 'parent', 'delivered', 'normal', ?, ?)"
      )
      .bind(
        parentId,
        TEST_AGENT_ID,
        JSON.stringify({ options: ['optionA'] }),
        new Date(Date.now() + 60_000).toISOString(),
      )
      .run();

    const res = await signedFetch({
      type: 3,
      channel_id: CHANNEL_ID,
      data: { custom_id: 'b077e0fb:rm -rf / --no-preserve-root' },
      message: { content: 'Pick one:' },
    });

    expect(res.status).toBe(400);
    const reply = await env.DB
      .prepare('SELECT body FROM messages WHERE reply_to = ?')
      .bind(parentId)
      .first<{ body: string }>();
    expect(reply).toBeNull();
    const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(parentId).first<{ status: string }>();
    expect(parent?.status).toBe('delivered');
  });

  it('approves a join request from a Discord button callback', async () => {
    const requestId = 'a077e0fa00000001aabbccdd00000001';
    await env.DB
      .prepare("INSERT INTO join_requests (id, name, poll_token, status) VALUES (?, ?, ?, 'pending')")
      .bind(requestId, 'discord-join-test', 'jt_discord_join_test')
      .run();

    const payload = {
      type: 3,
      channel_id: CHANNEL_ID,
      data: { custom_id: `join:approve:${requestId}` },
      message: { content: 'Join request for discord-join-test' },
    };

    const res = await signedFetch(payload);
    expect(res.status).toBe(200);
    const data = await res.json() as InteractionResponse;
    expect(data.type).toBe(7);
    expect(data.data?.content).toContain('Join request for discord-join-test');
    expect(data.data?.content).toContain('✅ Approved');
    expect(data.data?.components).toEqual([]);

    const approved = await env.DB
      .prepare('SELECT status, api_key_id, api_key FROM join_requests WHERE id = ?')
      .bind(requestId)
      .first<{ status: string; api_key_id: string | null; api_key: string | null }>();

    expect(approved?.status).toBe('approved');
    expect(approved?.api_key_id).toBeTruthy();
    expect(approved?.api_key?.startsWith('hb_')).toBe(true);
  });

  it('rejects join approvals from non-admin discord bosses', async () => {
    const requestId = 'a077e0fa00000009aabbccdd00000009';
    await env.DB
      .prepare("INSERT INTO join_requests (id, name, poll_token, status) VALUES (?, ?, ?, 'pending')")
      .bind(requestId, 'discord-join-viewer', 'jt_discord_join_viewer')
      .run();
    await env.DB.prepare(
      "INSERT INTO bosses (id, name, role, discord_user_id) VALUES (?, ?, ?, ?)"
    ).bind('discord-viewer-boss', 'Discord Viewer', 'viewer', 'discord-viewer-user').run();

    const payload = {
      type: 3,
      channel_id: CHANNEL_ID,
      member: { user: { id: 'discord-viewer-user' } },
      data: { custom_id: `join:approve:${requestId}` },
      message: { content: 'Join request for discord-join-viewer' },
    };

    const res = await signedFetch(payload);
    expect(res.status).toBe(403);
    expect(await res.text()).toBe('admin required');

    const pending = await env.DB
      .prepare('SELECT status FROM join_requests WHERE id = ?')
      .bind(requestId)
      .first<{ status: string }>();
    expect(pending?.status).toBe('pending');

    await env.DB.prepare('DELETE FROM bosses WHERE id = ?').bind('discord-viewer-boss').run();
  });

  it('copies action metadata into button replies', async () => {
    const parentId = 'b077ac71000000020000000000000002';
    const actions = { Approve: 'aid merge t-123', Reject: 'echo rejected' };
    await env.DB
      .prepare(
        "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'boss_to_agent', 'async', 'discord', 'with actions', 'sent', 'normal', ?)"
      )
      .bind(parentId, TEST_AGENT_ID, JSON.stringify({ actions }))
      .run();

    const payload = {
      type: 3,
      channel_id: CHANNEL_ID,
      data: { custom_id: 'b077ac71:Approve' },
    };

    const res = await signedFetch(payload);
    expect(res.status).toBe(200);

    const reply = await env.DB
      .prepare('SELECT metadata FROM messages WHERE reply_to = ? ORDER BY created_at DESC LIMIT 1')
      .bind(parentId)
      .first<{ metadata: string | null }>();

    expect(reply).not.toBeNull();
    expect(reply?.metadata).not.toBeNull();
    expect(JSON.parse(reply!.metadata!)).toEqual({ action: 'aid merge t-123' });
  });

  it('returns 400 when channel_id is missing', async () => {
    const payload = {
      type: 2,
      data: { name: 'msg', options: [{ name: 'message', value: 'hello' }] },
    };
    const res = await signedFetch(payload);
    expect(res.status).toBe(400);
    expect(await res.text()).toBe('missing channel_id');
  });

  it('returns an ephemeral notice when the channel is unknown', async () => {
    const payload = {
      type: 2,
      channel_id: 'missing-channel',
      data: { name: 'msg', options: [{ name: 'message', value: 'hello' }] },
    };
    const res = await signedFetch(payload);
    expect(res.status).toBe(200);
    const data = await res.json() as InteractionResponse;
    expect(data.type).toBe(4);
    expect(data.data?.content).toBe('No agent configured for this channel.');
    expect(data.data?.flags).toBe(64);
  });

  it('rejects invalid signatures', async () => {
    const body = JSON.stringify({ type: 1 });
    const timestamp = String(Math.floor(Date.now() / 1000));
    const res = await SELF.fetch(BASE_URL, {
      method: 'POST',
      body,
      headers: {
        'Content-Type': 'application/json',
        'X-Signature-Timestamp': timestamp,
        'X-Signature-Ed25519': '00'.repeat(64),
      },
    });
    expect(res.status).toBe(401);
    expect(await res.text()).toBe('invalid signature');
  });

  it('rejects stale timestamps', async () => {
    const payload = { type: 1 };
    const staleTimestamp = String(Math.floor(Date.now() / 1000) - 301);
    const res = await signedFetch(payload, {}, staleTimestamp);

    expect(res.status).toBe(401);
    expect(await res.text()).toBe('stale interaction');
  });

  it('rejects requests missing signature headers', async () => {
    const res = await SELF.fetch(BASE_URL, {
      method: 'POST',
      body: JSON.stringify({ type: 1 }),
    });
    expect(res.status).toBe(401);
    expect(await res.text()).toBe('missing signature headers');
  });
});

async function signedFetch(body: BodyInput, extraHeaders: HeaderMap = {}, timestamp = String(Math.floor(Date.now() / 1000))): Promise<Response> {
  const payload = typeof body === 'string' ? body : JSON.stringify(body);
  const signature = await signPayload(payload, timestamp);
  const headers: HeaderMap = {
    'Content-Type': 'application/json',
    'X-Signature-Timestamp': timestamp,
    'X-Signature-Ed25519': signature,
    ...extraHeaders,
  };
  return SELF.fetch(BASE_URL, { method: 'POST', body: payload, headers });
}

async function signPayload(body: string, timestamp: string): Promise<string> {
  const data = TEXT_ENCODER.encode(timestamp + body);
  const signatureBuffer = await crypto.subtle.sign('Ed25519', testPrivateKey, data);
  return bufferToHex(signatureBuffer);
}

function bufferToHex(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  return Array.from(bytes)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}
