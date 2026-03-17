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

const TEST_AGENT_ID = getTestAgentId();

let testPrivateKey: CryptoKey;

beforeAll(async () => {
  await seedDatabase();
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
    const responseBody = await res.json();
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
        "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'blocking', 'discord', 'parent', 'delivered', 'normal')"
      )
      .bind(parentId, TEST_AGENT_ID)
      .run();

    const payload = {
      type: 3,
      channel_id: CHANNEL_ID,
      data: { custom_id: 'b077e0fa:optionA' },
      message: { content: 'Pick one:' },
    };

    const res = await signedFetch(payload);
    expect(res.status).toBe(200);
    const data = await res.json();
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
    const data = await res.json();
    expect(data.type).toBe(4);
    expect(data.data?.content).toBe('No agent configured for this channel.');
    expect(data.data?.flags).toBe(64);
  });

  it('rejects invalid signatures', async () => {
    const body = JSON.stringify({ type: 1 });
    const timestamp = new Date().toISOString();
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

  it('rejects requests missing signature headers', async () => {
    const res = await SELF.fetch(BASE_URL, {
      method: 'POST',
      body: JSON.stringify({ type: 1 }),
    });
    expect(res.status).toBe(401);
    expect(await res.text()).toBe('missing signature headers');
  });
});

async function signedFetch(body: BodyInput, extraHeaders: HeaderMap = {}): Promise<Response> {
  const payload = typeof body === 'string' ? body : JSON.stringify(body);
  const timestamp = new Date().toISOString();
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
