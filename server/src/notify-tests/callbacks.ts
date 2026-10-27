// Agent callbacks with absent recipients, rejected transport and guarded delivery updates.
// Registers database integration cases with controlled fetch responses and complete request checks.

import { env } from 'cloudflare:test';
import { expect, it, vi } from 'vitest';
import { getTestAgentId } from '../test-helpers';
import { notifyAgentCallback, notifyTargetAgent } from '../notify';
import type { MessageRow } from '../types';
import { fakeMessage } from './support';

it.each([
  // Default seeded agent has no callback_url — should return without error
  ['returns silently when agent has no callback_url set', null],
  ['returns silently when agent does not exist', 'nonexistent-agent-id'],
])('notifyAgentCallback %s', async (_, id) => {
  const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(new Response(null, { status: 204 }));
  vi.stubGlobal('fetch', fetchMock);
  await expect(notifyAgentCallback(env, id ?? getTestAgentId(), fakeMessage)).resolves.toBeUndefined();
  expect(fetchMock).not.toHaveBeenCalled();
});

it('notifyAgentCallback does not throw when callback fetch fails', async () => {
  const agentId = getTestAgentId();
  const callbackUrl = 'http://0.0.0.0:1/callback';
  const body = JSON.stringify(fakeMessage);
  // Set a callback_url that will fail (unreachable host)
  await env.DB.prepare('UPDATE api_keys SET callback_url = ? WHERE id = ?')
    .bind(callbackUrl, agentId).run();
  const fetchMock = vi.fn<typeof fetch>().mockRejectedValue(new Error('callback unavailable'));
  vi.stubGlobal('fetch', fetchMock);
  try {
    await expect(notifyAgentCallback(env, agentId, fakeMessage)).resolves.toBeUndefined();
    expect(fetchMock).toHaveBeenCalledExactlyOnceWith(callbackUrl, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body,
    });
  } finally {
    // Clean up: remove callback_url so other tests aren't affected
    await env.DB.prepare('UPDATE api_keys SET callback_url = NULL WHERE id = ?').bind(agentId).run();
  }
});

it.each<[
  string, number | null, MessageRow['status'], MessageRow['direction'], boolean, MessageRow['status'],
]>([
  ['notifyTargetAgent marks a sent a2a message delivered after callback acceptance',
    204, 'sent', 'agent_to_agent', true, 'delivered'],
  ['notifyTargetAgent keeps a message sent after HTTP rejection',
    500, 'sent', 'agent_to_agent', true, 'sent'],
  ['notifyTargetAgent keeps a message sent after transport rejection',
    null, 'sent', 'agent_to_agent', true, 'sent'],
  ['notifyTargetAgent preserves a replied message after callback acceptance',
    204, 'replied', 'agent_to_agent', true, 'replied'],
  ['notifyTargetAgent preserves boss message status after callback acceptance',
    204, 'sent', 'boss_to_agent', true, 'sent'],
  ['notifyAgentCallback preserves status when delivery tracking is not requested',
    204, 'sent', 'agent_to_agent', false, 'sent'],
])('%s', async (_, response, status, direction, markDelivered, expected) => {
  const agentId = getTestAgentId();
  const messageId = 'notify-target-a2a';
  await env.DB.prepare('UPDATE api_keys SET callback_url = ? WHERE id = ?')
    .bind('https://peer.test/callback', agentId).run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO messages (id, agent_id, direction, mode, channel, body, status, priority, ' +
    "target_agent_id) VALUES (?, ?, ?, 'async', 'api', 'Callback pickup', ?, 'normal', ?)"
  ).bind(messageId, agentId, direction, status, agentId).run();
  const message: MessageRow = { ...fakeMessage, id: messageId, direction, status };
  const body = JSON.stringify(message);
  const fetchMock = vi.fn<typeof fetch>();
  if (response === null) fetchMock.mockRejectedValue(new Error('callback unavailable'));
  else fetchMock.mockResolvedValue(new Response(null, { status: response }));
  vi.stubGlobal('fetch', fetchMock);
  try {
    await (markDelivered
      ? notifyTargetAgent(env, agentId, message)
      : notifyAgentCallback(env, agentId, message));
    expect(fetchMock).toHaveBeenCalledExactlyOnceWith('https://peer.test/callback', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body,
    });
    const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(messageId).first<{ status: string }>();
    expect(row?.status).toBe(expected);
  } finally {
    await env.DB.prepare('UPDATE api_keys SET callback_url = NULL WHERE id = ?').bind(agentId).run();
  }
});
