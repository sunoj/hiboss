// Linked follow-up and reaction regressions through authenticated Worker APIs.
// Exercises D1 persistence, boss history/detail/delta, and decision integrity.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { expireMessageOptions, withdrawResolvedOptions } from './message-options';
import { storeMessageReaction } from './message-reactions';
import type { MessageRow } from '../types';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { testJson } from '../test-request';

const token = 'linked-thread-boss-token';
const boss = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
const base = 'https://test.local';
type Row = { id: string; reply_to: string | null; metadata: { reactions?: unknown[] }; session_id?: string };

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Thread boss', 'admin', token, 'thread-boss');
});

async function question(id: string): Promise<void> {
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, created_at, updated_at, metadata, expires_at)
    VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Choose', 'sent',
      '2000-01-01 00:00:00', '2000-01-01 00:00:00', '{"ask_deadline":true}',
      '2099-01-01T00:00:00Z')`)
    .bind(id, getTestAgentId()).run();
}

async function post(path: string, body: unknown, headers = authHeaders()): Promise<Response> {
  return SELF.fetch(`${base}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
}

it('links follow-ups to questions and boss replies without deciding the question', async () => {
  await question('thread-root');
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)')
    .bind('thread-session', getTestAgentId()).run();
  await env.DB.prepare('UPDATE messages SET session_id = ? WHERE id = ?')
    .bind('thread-session', 'thread-root').run();
  const first = await testJson(201, post('/api/messages/thread-root/reply', { body: 'More context' })) as Row;
  expect(first.reply_to).toBe('thread-root');
  const root = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
    .bind('thread-root').first<{ status: string }>();
  expect(root?.status).toBe('sent');
  const polling = await post('/api/messages/thread-root/poll?timeout=1', {});
  expect(polling.status).toBe(200);
  expect((await polling.json() as { replies: Row[] }).replies).toEqual([]);
  const reply = await testJson(201,
    post('/api/boss/messages/thread-root/reply', { body: 'Proceed' }, boss)) as Row;
  const last = await testJson(201, post(`/api/messages/${reply.id}/reply`, { body: 'Working on it' })) as Row;
  expect(last.reply_to).toBe(reply.id);
  expect(first.session_id).toBe('thread-session');
  expect(last.session_id).toBe('thread-session');
  const detail = await SELF.fetch(`${base}/api/boss/messages/thread-root`, { headers: boss });
  const thread = await detail.json() as Row & { replies: Row[] };
  expect(thread.replies.map(row => row.id)).toEqual(expect.arrayContaining([first.id, reply.id, last.id]));
  for (const suffix of ['?direction=all', '?direction=all&updated_after=2000-01-01%2000:00:00']) {
    const response = await SELF.fetch(`${base}/api/boss/messages${suffix}`, { headers: boss });
    const page = await response.json() as { messages: Row[] };
    expect(page.messages.find(row => row.id === last.id)?.reply_to).toBe(reply.id);
  }
});

it('deduplicates actor reactions and exposes changed metadata through boss reads', async () => {
  await question('thread-react');
  for (const headers of [authHeaders(), boss]) {
    const path = headers === boss ? '/api/boss/messages/thread-react/react' : '/api/messages/thread-react/react';
    const responses = await Promise.all([post(path, { emoji: '👍' }, headers), post(path, { emoji: '👍' }, headers)]);
    expect(responses.map(response => response.status)).toEqual([200, 200]);
  }
  for (const path of ['/api/boss/messages/thread-react',
    '/api/boss/messages', '/api/boss/messages?updated_after=2001-01-01%2000:00:00']) {
    const response = await SELF.fetch(`${base}${path}`, { headers: boss });
    const data = await response.json() as Row & { messages?: Row[] };
    const row = data.messages ? data.messages.find(message => message.id === 'thread-react') : data;
    expect(row?.metadata.reactions).toEqual([
      { emoji: '👍', actor: 'agent', actor_id: getTestAgentId(), created_at: expect.any(String) },
      { emoji: '👍', actor: 'boss', actor_id: 'thread-boss', created_at: expect.any(String) },
    ]);
  }
});

it.each(['boss_id', 'user'])('recognizes legacy %s entries when deduplicating boss reactions', async key => {
  const id = `legacy-${key}`;
  await question(id);
  await env.DB.prepare('UPDATE messages SET metadata = ? WHERE id = ?')
    .bind(JSON.stringify({ reactions: [{ emoji: '👍', [key]: 'thread-boss' }] }), id).run();
  expect((await post(`/api/boss/messages/${id}/react`, { emoji: '👍' }, boss)).status).toBe(200);
  const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
    .bind(id).first<{ metadata: string }>();
  expect(JSON.parse(row?.metadata ?? '{}').reactions).toHaveLength(1);
});

it.each(['cleanup', 'expiry', 'default'])('preserves a reaction added after the %s snapshot', async kind => {
  const id = `metadata-race-${kind}`;
  await question(id);
  await env.DB.prepare('UPDATE messages SET metadata = ? WHERE id = ?')
    .bind(JSON.stringify({ options: ['A'], actions: { A: 'go' },
      ...(kind === 'default' ? { default_option: 'A' } : {}) }), id).run();
  const snapshot = await env.DB.prepare('SELECT * FROM messages WHERE id = ?')
    .bind(id).first<MessageRow>();
  expect(snapshot).not.toBeNull();
  await storeMessageReaction(env, id, 'agent', 'concurrent-agent', '👍');
  if (kind === 'cleanup') await withdrawResolvedOptions(env, getTestAgentId(), snapshot!, 'A');
  else await expireMessageOptions(env, getTestAgentId(), snapshot!);
  const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
    .bind(id).first<{ metadata: string }>();
  expect(JSON.parse(row!.metadata)).toMatchObject({
    reactions: [{ emoji: '👍', actor: 'agent', actor_id: 'concurrent-agent' }],
    ...(kind === 'cleanup' ? { options_resolved: true, selected_option: 'A' } : { options_expired: true }),
  });
  expect(JSON.parse(row!.metadata)).not.toHaveProperty('actions');
});
