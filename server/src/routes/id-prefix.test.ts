// Tests the primary-key range lookup that replaced `id = ? OR id LIKE ?` message scans.
// Covers exact-first ordering, prefixes, literal LIKE wildcards and the empty id.
// Depends on cloudflare:test D1 and the shared test schema.
import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase } from '../test-helpers';
import { findMessageByIdPrefix, idPrefixRange } from './id-prefix';

beforeAll(async () => {
  await seedDatabase();
  for (const id of ['pfx-ab', 'pfx-a', 'pfx-b', 'pfx%z']) {
    await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status)
      VALUES (?, 'test-agent-id', 'agent_to_boss', 'async', 'api', 'x', 'sent')`).bind(id).run();
  }
});

describe('idPrefixRange', () => {
  it('bounds the ids that start with the prefix', () => {
    expect(idPrefixRange('abc')).toEqual(['abc', 'abd']);
    expect(idPrefixRange('')).toEqual(['', '']);
  });
});

describe('findMessageByIdPrefix', () => {
  it.each([
    ['pfx-a', 'pfx-a'], ['pfx-ab', 'pfx-ab'], ['pfx-', 'pfx-a'], ['pfx-b', 'pfx-b'],
    ['pfx%', 'pfx%z'], ['pfx_', null], ['pfx-c', null], ['', null],
  ])('resolves %j to %j', async (input, expected) => {
    expect((await findMessageByIdPrefix(env.DB, input))?.id ?? null).toBe(expected);
  });

  it('joins the agent name when asked', async () => {
    expect((await findMessageByIdPrefix(env.DB, 'pfx-a', true))?.agent_name).toBeTruthy();
  });
});
