// Tests for reactions endpoints.
// Covers posting reactions and fetching reactions from metadata.
// Depends on cloudflare:test, vitest, and reactions.ts.

import { describe, it, expect, beforeAll } from 'vitest';
import { env, SELF } from 'cloudflare:test';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('POST /api/messages/:id/react', () => {
  const agentId = getTestAgentId();

  it('returns 400 when emoji missing', async () => {
    // Insert a message to react to
    const msgId = 'react-test-1';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel) VALUES (?, ?, 'boss_to_agent', 'async', 'Test msg', 'sent', 'telegram')"
    ).bind(msgId, agentId).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toBe('emoji is required');
  });

  it('returns 404 for unknown message', async () => {
    const res = await SELF.fetch('https://test.local/api/messages/unknown-msg-id/react', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👍' }),
    });
    expect(res.status).toBe(404);
    expect(await res.text()).toBe('not found');
  });

  it('returns 400 for non-telegram channel', async () => {
    // Test with 'api' channel which doesn't support reactions in the current implementation
    const msgId = 'react-test-api';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel) VALUES (?, ?, 'boss_to_agent', 'async', 'API msg', 'sent', 'api')"
    ).bind(msgId, agentId).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/react`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ emoji: '👍' }),
    });
    expect(res.status).toBe(400);
    expect(await res.text()).toBe('reactions not supported on this channel');
  });
});

describe('GET /api/messages/:id/reactions', () => {
  const agentId = getTestAgentId();

  it('returns empty array for message without reactions', async () => {
    const msgId = 'react-test-none';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel) VALUES (?, ?, 'boss_to_agent', 'async', 'No reactions', 'sent', 'api')"
    ).bind(msgId, agentId).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/reactions`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { reactions: any[] };
    expect(data.reactions).toEqual([]);
  });

  it('returns reactions from metadata', async () => {
    const msgId = 'react-test-meta';
    const reactions = [{ emoji: '🚀', user: 'agent-1' }];
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, channel, metadata) VALUES (?, ?, 'boss_to_agent', 'async', 'With meta reactions', 'sent', 'api', ?)"
    ).bind(msgId, agentId, JSON.stringify({ reactions })).run();

    const res = await SELF.fetch(`https://test.local/api/messages/${msgId}/reactions`, {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { reactions: any[] };
    expect(data.reactions).toEqual(reactions);
  });
});
