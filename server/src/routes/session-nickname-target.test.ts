// Worker API tests for --to nickname scoping, precedence, and resolved target receipts.
// Depends on real D1 sessions, the message endpoint, and seeded agent authentication.
import { testRequest, testJson } from '../test-request';
import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { inferSessionStatus } from './message-helpers';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('nick-target-agent', 'coral', await hashApiKey('hb_test_key_nickname_target_000')).run();
  await env.DB.prepare(`INSERT INTO projects (id, slug, display_name)
    VALUES ('nick-target-project', 'nick-target-project', 'Target'),
      ('nick-target-foreign', 'nick-target-foreign', 'Foreign')`).run();
});

async function session(
  id: string, nickname: string, project = 'nick-target-project', label = 'shared/main',
): Promise<void> {
  await env.DB.prepare(`INSERT INTO sessions (id, agent_id, project_id, label, nickname)
    VALUES (?, 'test-agent-id', ?, ?, ?)`).bind(id, project, label, nickname).run();
}

async function send(to: string, sender: string | null): Promise<Response> {
  return testRequest('POST', 'http://localhost/api/messages', authHeaders(),
    { body: 'Peer message', to, session_id: sender });
}

it('resolves an exact nickname in the sender project before label and agent id prefixes', async () => {
  await session('nick-target-sender', 'palm');
  await session('nick-target-peer', 'nick');
  await session('nick-target-prefix', 'gull', 'nick-target-project', 'nick/main');
  const data = await testJson(201, send('nick', 'nick-target-sender')) as {
    id: string; target: { id: string; nickname: string; label: string };
  };
  expect(data.target).toEqual({
    id: 'nick-target-peer', nickname: 'nick', label: 'nick-target-project/main',
  });
  const stored = await env.DB.prepare('SELECT target_session_id, direction FROM messages WHERE id = ?')
    .bind(data.id).first();
  expect(stored).toEqual({ target_session_id: 'nick-target-peer', direction: 'agent_to_agent' });
});

it('lets an agent name win over an exact label and a nickname from another agent', async () => {
  await session('nick-name-sender', 'tide');
  await session('nick-name-label', 'reef', 'nick-target-project', 'coral');
  await session('nick-name-nickname', 'coral');
  const data = await testJson(201, send('coral', 'nick-name-sender')) as { id: string };
  const stored = await env.DB.prepare('SELECT target_agent_id, target_session_id FROM messages WHERE id = ?')
    .bind(data.id).first();
  expect(stored).toEqual({ target_agent_id: 'nick-target-agent', target_session_id: null });
});

it('lets an exact label win over a nickname', async () => {
  await session('nick-label-sender', 'brine');
  await session('nick-label-peer', 'kelp', 'nick-target-project', 'lantern');
  await session('nick-label-nickname', 'lantern');
  const data = await testJson(201,
    send('lantern', 'nick-label-sender')) as { target: { id: string; nickname: string } };
  expect(data.target).toMatchObject({ id: 'nick-label-peer', nickname: 'kelp' });
});

it('resolves suffixes across agents and keeps idle peers deliverable with a warning', async () => {
  await session('nick-suffix-sender', 'lagoon');
  await session('nick-suffix-peer', 'otter-2');
  await env.DB.prepare(`UPDATE sessions SET agent_id = 'nick-target-agent',
    last_seen_at = datetime('now', '-2 hours') WHERE id = 'nick-suffix-peer'`).run();
  const data = await testJson(201,
    send('otter-2', 'nick-suffix-sender')) as { target: { id: string; nickname: string }; warning: string };
  expect(data.target).toMatchObject({ id: 'nick-suffix-peer', nickname: 'otter-2' });
  expect(data.warning).toContain('last seen');
});

it('does not resolve other projects, self, partial names, or names without a sender', async () => {
  await session('nick-scope-sender', 'mango');
  await session('nick-scope-foreign', 'orchid', 'nick-target-foreign');
  await session('nick-scope-peer', 'pearl');
  const cases: [string, string | null][] = [
    ['orchid', 'nick-scope-sender'], ['mango', 'nick-scope-sender'],
    ['pear', 'nick-scope-sender'], ['pearl', null],
  ];
  for (const [target, sender] of cases) {
    expect((await send(target, sender)).status).toBe(404);
  }
});

it('does not resolve completed or more than 24-hour-old sessions by nickname', async () => {
  await session('nick-inactive-sender', 'cove');
  await session('nick-inactive-done', 'heron');
  await session('nick-inactive-old', 'tern');
  await env.DB.prepare("UPDATE sessions SET status = 'completed' WHERE id = 'nick-inactive-done'").run();
  await env.DB.prepare(`UPDATE sessions SET last_seen_at = datetime('now', '-25 hours')
    WHERE id = 'nick-inactive-old'`).run();
  for (const target of ['heron', 'tern']) {
    expect((await send(target, 'nick-inactive-sender')).status).toBe(404);
  }
});

it('gives a revived session a free nickname instead of a live peer name', async () => {
  await session('nick-revive-holder', 'harbor');
  await session('nick-revive-old', 'harbor');
  await env.DB.prepare("UPDATE sessions SET status = 'completed' WHERE id = 'nick-revive-old'").run();
  await inferSessionStatus(env, 'test-agent-id', 'nick-revive-old', 'async', 'normal', 'Back');
  const rows = await env.DB.prepare(`SELECT id, nickname FROM sessions
    WHERE id IN ('nick-revive-holder', 'nick-revive-old') ORDER BY id`).all();
  expect(rows.results).toEqual([
    { id: 'nick-revive-holder', nickname: 'harbor' }, { id: 'nick-revive-old', nickname: 'harbor-2' },
  ]);
});
