// Integration tests for agent callback notification.
// Tests notifyAgentCallback best-effort delivery behavior.
// Depends on cloudflare:test D1 and shared test helpers.

import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, getTestAgentId } from './test-helpers';
import { notifyAgentCallback } from './notify';
import type { MessageRow } from './types';

const fakeMessage: MessageRow = {
  id: 'msg-test-001',
  agent_id: 'test-agent-id',
  direction: 'boss_to_agent',
  mode: 'async',
  channel: 'telegram',
  body: 'Test callback message',
  status: 'sent',
  reply_to: null,
  priority: 'normal',
  metadata: null,
  created_at: '2026-03-16T00:00:00Z',
  updated_at: '2026-03-16T00:00:00Z',
};

beforeAll(async () => {
  await seedDatabase();
});

describe('notifyAgentCallback', () => {
  it('returns silently when agent has no callback_url set', async () => {
    const agentId = getTestAgentId();
    // Default seeded agent has no callback_url — should return without error
    await expect(
      notifyAgentCallback(env as never, agentId, fakeMessage),
    ).resolves.toBeUndefined();
  });

  it('returns silently when agent does not exist', async () => {
    await expect(
      notifyAgentCallback(env as never, 'nonexistent-agent-id', fakeMessage),
    ).resolves.toBeUndefined();
  });

  it('does not throw when callback fetch fails', async () => {
    const agentId = getTestAgentId();
    // Set a callback_url that will fail (unreachable host)
    await env.DB.prepare('UPDATE api_keys SET callback_url = ? WHERE id = ?')
      .bind('http://0.0.0.0:1/callback', agentId)
      .run();

    await expect(
      notifyAgentCallback(env as never, agentId, fakeMessage),
    ).resolves.toBeUndefined();

    // Clean up: remove callback_url so other tests aren't affected
    await env.DB.prepare('UPDATE api_keys SET callback_url = NULL WHERE id = ?')
      .bind(agentId)
      .run();
  });
});
