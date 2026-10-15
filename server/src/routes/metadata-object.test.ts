// Metadata normalization regressions against real D1 writes.
// Exercises expiry, immediate/queued delivery, failures, and reaction storage.
import { env } from 'cloudflare:test';
import { Hono } from 'hono';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import type { Env, MessageRow } from '../types';
import { getTestAgentId, seedDatabase } from '../test-helpers';
import { handleScheduled } from '../scheduled';
import { expireWithoutDefault } from './message-options';
import { deliverLegacySend } from './message-send-legacy';
import { persistDeliveryFailure } from './delivery';
import { removeMessageReaction, storeMessageReaction } from './message-reactions';

beforeAll(seedDatabase);
afterEach(() => vi.unstubAllGlobals());

const reaction = { emoji: '👍', actor: 'boss', actor_id: 'existing' };
const object = { preserved: true, reactions: [reaction] };
const cases = [null, '', 'null', '[]', '"s"', '1', 'invalid JSON', JSON.stringify(object)];

async function insert(id: string, metadata: string | null): Promise<MessageRow> {
  const row = await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata)
    VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'Hello', 'sent', ?) RETURNING *`)
    .bind(`${id}-${crypto.randomUUID()}`, getTestAgentId(), metadata).first<MessageRow>();
  if (!row) throw new Error('message insert failed');
  return row;
}

async function read(id: string): Promise<{ status: string; metadata: Record<string, unknown> }> {
  const row = await env.DB.prepare('SELECT status, metadata FROM messages WHERE id = ?')
    .bind(id).first<{ status: string; metadata: string }>();
  if (!row) throw new Error('message missing');
  return { status: row.status, metadata: JSON.parse(row.metadata) as Record<string, unknown> };
}

it.each(cases)('normalizes stored metadata %j across expiry and delivery bookkeeping', async raw => {
  const expected = raw === JSON.stringify(object) ? object : {};
  const expired = await insert('normalize-expiry', raw);
  expect(await expireWithoutDefault(env, getTestAgentId(), expired)).toBe(true);
  expect(await read(expired.id)).toEqual({
    status: 'expired', metadata: { ...expected, options_expired: true },
  });
  for (const queued of [false, true]) {
    await checkDelivery(raw, expected, queued);
  }
  const failed = await insert('normalize-failure', raw);
  await persistDeliveryFailure(env, failed.id, 'provider failed');
  expect((await read(failed.id)).metadata).toEqual({ ...expected, delivery_error: 'provider failed' });
  const reacted = await insert('normalize-reaction', raw);
  expect(await storeMessageReaction(env, reacted.id, 'agent', 'new', '✅')).toBe(true);
  await removeMessageReaction(env, reacted.id, 'agent', 'new', '✅');
  expect((await read(reacted.id)).metadata).toEqual({
    ...expected, reactions: expected === object ? [reaction] : [],
  });
});

async function checkDelivery(
  raw: string | null, expected: Record<string, unknown>, queued: boolean,
): Promise<void> {
  const message = await insert(`normalize-delivery-${queued}`, null);
  const config = { webhook_url: 'https://discord.com/api/webhooks/test/test' };
  // Change the stored value after delivery reads it, exercising the database-side writer.
  vi.stubGlobal('fetch', vi.fn(async () => {
    await env.DB.prepare('UPDATE messages SET metadata = ? WHERE id = ?').bind(raw, message.id).run();
    return new Response(JSON.stringify({ id: 'provider-id' }));
  }));
  if (queued) {
    await env.DB.prepare(`INSERT OR REPLACE INTO channel_configs (agent_id, channel, config, enabled)
      VALUES (?, 'discord', ?, 1)`).bind(getTestAgentId(), JSON.stringify(config)).run();
    await env.DB.prepare(`INSERT INTO delivery_queue (message_id, agent_id, channel, config, scheduled_at)
      VALUES (?, ?, 'discord', ?, '2000-01-01T00:00:00Z')`)
      .bind(message.id, getTestAgentId(), JSON.stringify(config)).run();
    await handleScheduled(env);
  } else {
    const app = new Hono<{ Bindings: Env }>();
    app.post('/', async c => {
      await deliverLegacySend(c, message, [{ channel: 'discord', config }],
        undefined, undefined, undefined, undefined);
      return c.json({ ok: true });
    });
    expect((await app.request('https://test.local/', { method: 'POST' }, env)).status).toBe(200);
  }
  expect(await read(message.id)).toEqual({
    status: 'delivered', metadata: { ...expected, discord_message_id: 'provider-id' },
  });
}
