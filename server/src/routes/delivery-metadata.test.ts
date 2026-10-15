// Delivery regression tests with real D1 and mocked provider responses.
// Adds reactions after delivery reads, before its final metadata update.
import { env, SELF } from 'cloudflare:test';
import { Hono } from 'hono';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import type { Env, MessageRow } from '../types';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';
import { storeMessageReaction } from './message-reactions';
import { deliverLegacySend } from './message-send-legacy';
import { handleScheduled } from '../scheduled';

beforeAll(seedDatabase);
afterEach(() => vi.unstubAllGlobals());

async function insert(id: string): Promise<MessageRow> {
  const row = await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata)
    VALUES (?, ?, 'agent_to_boss', 'async', 'discord', 'Hello', 'sent', ?)
    RETURNING *`).bind(id, getTestAgentId(), JSON.stringify({ preserved: true })).first<MessageRow>();
  if (!row) throw new Error('message insert failed');
  return row;
}

async function configure(): Promise<void> {
  await env.DB.prepare(`INSERT OR REPLACE INTO channel_configs (agent_id, channel, config, enabled)
    VALUES (?, 'discord', ?, 1)`).bind(getTestAgentId(), JSON.stringify({
      webhook_url: 'https://discord.com/api/webhooks/test/test',
    })).run();
}

function provider(id: string): void {
  vi.stubGlobal('fetch', vi.fn(async () => {
    await storeMessageReaction(env, id, 'boss', 'concurrent-boss', '👍');
    return new Response(JSON.stringify({ id: 'discord-delivery-id' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }));
}

async function expectMetadata(id: string): Promise<void> {
  const row = await env.DB.prepare('SELECT metadata, status FROM messages WHERE id = ?')
    .bind(id).first<{ metadata: string; status: string }>();
  expect(row?.status).toBe('delivered');
  expect(JSON.parse(row?.metadata ?? '{}')).toMatchObject({
    preserved: true, discord_message_id: 'discord-delivery-id',
    reactions: [{ emoji: '👍', actor: 'boss', actor_id: 'concurrent-boss' }],
  });
}

it('preserves concurrent reactions during immediate delivery', async () => {
  const message = await insert('immediate-metadata-race');
  provider(message.id);
  const app = new Hono<{ Bindings: Env }>();
  app.post('/', async c => {
    await deliverLegacySend(c, message, [{ channel: 'discord', config: {
      webhook_url: 'https://discord.com/api/webhooks/test/test',
    } }], undefined, undefined, undefined, undefined);
    return c.json({ ok: true });
  });
  await app.request('https://test.local/', { method: 'POST' }, env);
  await expectMetadata(message.id);
});

it('preserves concurrent reactions during queued delivery', async () => {
  const message = await insert('queued-metadata-race');
  await configure();
  await env.DB.prepare(`INSERT INTO delivery_queue
    (message_id, agent_id, channel, config, scheduled_at)
    VALUES (?, ?, 'discord', ?, '2000-01-01T00:00:00Z')`)
    .bind(message.id, getTestAgentId(), JSON.stringify({
      webhook_url: 'https://discord.com/api/webhooks/test/test',
    })).run();
  provider(message.id);
  await handleScheduled(env);
  await expectMetadata(message.id);
});

it('persists Discord follow-up delivery IDs alongside concurrent metadata', async () => {
  await insert('discord-followup-parent');
  await configure();
  vi.stubGlobal('fetch', vi.fn(async () => {
    const reply = await env.DB.prepare('SELECT id FROM messages WHERE reply_to = ?')
      .bind('discord-followup-parent').first<{ id: string }>();
    if (!reply) throw new Error('reply missing');
    await storeMessageReaction(env, reply.id, 'boss', 'concurrent-boss', '👍');
    return new Response(JSON.stringify({ id: 'discord-followup-id' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }));
  const response = await SELF.fetch('https://test.local/api/messages/discord-followup-parent/reply', {
    method: 'POST', headers: authHeaders(), body: JSON.stringify({ body: 'Follow-up' }),
  });
  expect(response.status).toBe(201);
  const reply = await response.json() as { id: string };
  const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
    .bind(reply.id).first<{ metadata: string }>();
  expect(JSON.parse(row?.metadata ?? '{}')).toMatchObject({
    discord_message_id: 'discord-followup-id',
    reactions: [{ actor: 'boss', actor_id: 'concurrent-boss' }],
  });
});
