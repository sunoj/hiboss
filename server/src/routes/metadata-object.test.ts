// Metadata normalization regressions against real D1 writes.
// Exercises expiry, delivery failures, and reaction storage.
import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import type { MessageRow } from '../types';
import { getTestAgentId, seedDatabase } from '../test-helpers';
import { expireWithoutDefault } from './message-options';
import { persistDeliveryFailure } from './delivery';
import { removeMessageReaction, storeMessageReaction } from './message-reactions';

beforeAll(seedDatabase);

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
  expect(await expireWithoutDefault(env, expired)).toBe(true);
  expect(await read(expired.id)).toEqual({
    status: 'expired', metadata: { ...expected, options_expired: true },
  });
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
