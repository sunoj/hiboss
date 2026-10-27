// Worker integration coverage for incremental and legacy boss message history.
// Exercises timestamp validation, filtering, paging, and access with real D1.
import { testRequest, testJson } from '../test-request';
import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, seedBossToken } from '../test-helpers';
import type { MessageResponse, MessageRow } from '../types';
import { validMessageCursor } from './boss-message-history';

const TOKEN = `hb_boss_${'cd'.repeat(16)}`;
const EMPTY_TOKEN = `hb_boss_${'ef'.repeat(16)}`;
const CURSOR = '2026-01-02 03:04:05';
const LATER = '2026-01-02 03:04:06';
const AGENTS = ['delta-agent-one', 'delta-agent-two', 'delta-agent-hidden'];
type Page = { messages: MessageResponse[]; total: number; cursor?: string; has_more?: boolean };

beforeAll(async () => {
  await seedDatabase();
  const boss = await seedBossToken('Delta Boss', 'manager', TOKEN);
  await seedBossToken('Empty Delta Boss', 'manager', EMPTY_TOKEN);
  for (const id of AGENTS) {
    await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(id, id, id).run();
  }
  for (const id of AGENTS.slice(0, 2)) {
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(boss, id).run();
  }
  await env.DB.prepare('INSERT INTO sessions (id, agent_id, label, branch) VALUES (?, ?, ?, ?)')
    .bind('delta-session', AGENTS[0], 'History', 'feature').run();
  const fixtures = [
    ['delta-old', AGENTS[0], 'agent_to_boss', '2026-01-02 03:04:04', '2026-02-05 00:00:00', 'sent', 'high'],
    ['delta-b', AGENTS[1], 'boss_to_agent', CURSOR, '2026-02-04 00:00:00', 'sent', 'normal'],
    ['delta-a', AGENTS[0], 'agent_to_boss', CURSOR, '2026-02-03 00:00:00', 'sent', 'high'],
    ['delta-c', AGENTS[0], 'agent_to_boss', LATER, '2026-02-02 00:00:00', 'read', 'high'],
    ['delta-hidden', AGENTS[2], 'agent_to_boss', LATER, '2026-02-01 00:00:00', 'sent', 'high'],
  ];
  for (const [id, agent, direction, updated, created, status, priority] of fixtures) {
    await env.DB.prepare(
      `INSERT INTO messages (id, agent_id, direction, updated_at, created_at, status, priority,
        mode, channel, body, session_id, metadata, reply_to) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(id, agent, direction, updated, created, status, priority, 'async', 'api',
      `History ${id}`, agent === AGENTS[0] ? 'delta-session' : null, '{"marker":true}',
      id === 'delta-b' ? 'delta-old' : null).run();
  }
});

async function request(params: Record<string, string> = {}, token = TOKEN): Promise<Response> {
  return testRequest('GET', `https://test.local/api/boss/messages?${new URLSearchParams(params)}`,
    { Authorization: `Bearer ${token}` });
}

async function delta(params: Record<string, string> = {}, token = TOKEN): Promise<Page> {
  const response = await request({ direction: 'all', updated_after: CURSOR, ...params }, token);
  expect(response.status).toBe(200);
  return response.json() as Promise<Page>;
}

describe('boss message delta', () => {
  it('includes the cursor second and orders by updated_at then id across accessible agents', async () => {
    const page = await delta();
    expect(page.messages.map(message => message.id)).toEqual(['delta-a', 'delta-b', 'delta-c']);
    expect(page).toMatchObject({ total: 3, cursor: LATER, has_more: false });
    expect(page.messages.map(message => message.updated_at)).toEqual([CURSOR, CURSOR, LATER]);
    expect(page.messages[0]).toMatchObject({
      agent_name: AGENTS[0], session_label: 'History', session_branch: 'feature', metadata: { marker: true },
    });
  });

  it('returns at most N rows and has_more whenever exactly N rows are returned', async () => {
    const page = await delta({ limit: '2' });
    expect(page.messages.map(message => message.id)).toEqual(['delta-a', 'delta-b']);
    expect(page).toMatchObject({ total: 3, cursor: CURSOR, has_more: true });
    expect(await delta({ limit: '3' })).toMatchObject({ cursor: LATER, has_more: true });
    expect(await delta({ limit: '4' })).toMatchObject({ cursor: LATER, has_more: false });
  });

  it('keeps offset and all existing message filters', async () => {
    const filtered = await delta({
      agent: 'delta-agent-o', session: 'delta-session', unread: 'true', priority: 'high,critical',
      search: 'History delta-a',
    });
    expect(filtered.messages.map(message => message.id)).toEqual(['delta-a']);
    const offset = await delta({ offset: '2', limit: '1' });
    expect(offset.messages.map(message => message.id)).toEqual(['delta-c']);
    expect(offset).toMatchObject({ cursor: LATER, has_more: true });
    const defaultDirection = await request({ updated_after: CURSOR });
    expect((await defaultDirection.json() as Page).messages.map(message => message.id))
      .toEqual(['delta-a', 'delta-c']);
  });

  it('retains the request cursor for every empty result path', async () => {
    const filters: Record<string, string>[] = [
      { updated_after: '2099-01-01 00:00:00' }, { agent: AGENTS[2] },
      { agent: 'missing' }, { search: 'missing' }, { offset: '100' },
    ];
    for (const params of filters) {
      const page = await delta(params);
      expect(page).toMatchObject({
        messages: [], cursor: params.updated_after ?? CURSOR, has_more: false,
      });
    }
    expect(await delta({}, EMPTY_TOKEN)).toEqual({ messages: [], total: 0, cursor: CURSOR, has_more: false });
  });

  it.each([
    '', 'garbage', '2026-01-02T03:04:05Z', '2026-1-02 03:04:05', '2026-02-30 03:04:05',
    '2025-02-29 03:04:05', '2026-13-02 03:04:05', '2026-01-02 24:00:00',
    '2026-01-02 03:60:05', '2026-01-02 03:04:60', '2026-01-02 03:04:05.123',
    '2026-01-02 03:04:05 ',
  ])('rejects malformed cursor %j even for a boss without accessible agents', async updated_after => {
    expect((await request({ updated_after })).status).toBe(400);
    expect((await request({ updated_after }, EMPTY_TOKEN)).status).toBe(400);
  });

  it('accepts a leap day in SQLite timestamp format', async () => {
    expect((await request({ updated_after: '2024-02-29 23:59:59' })).status).toBe(200);
  });

  it('adds a D1 cursor to the full response while preserving newest-first order', async () => {
    const before = await env.DB.prepare("SELECT datetime('now') AS cursor").first<string>('cursor');
    const response = await request({ direction: 'all', limit: '2', offset: '1' });
    const rows = await env.DB.prepare(
      `SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label,
        sessions.branch AS session_branch, sessions.status AS session_status FROM messages
        LEFT JOIN api_keys ON api_keys.id = messages.agent_id
        LEFT JOIN sessions ON sessions.id = messages.session_id WHERE messages.agent_id IN (?, ?)
        ORDER BY messages.created_at DESC, messages.id DESC LIMIT 2 OFFSET 1`
    ).bind(...AGENTS.slice(0, 2)).all<MessageRow>();
    const messages = rows.results.map(row => ({ ...row, metadata: JSON.parse(row.metadata ?? 'null') }));
    const page = await response.json() as Page;
    const after = await env.DB.prepare("SELECT datetime('now') AS cursor").first<string>('cursor');
    expect(page).toEqual({ messages, total: 4, cursor: expect.any(String) });
    expect(validMessageCursor(page.cursor!)).toBe(true);
    expect(page.cursor! >= before! && page.cursor! <= after!).toBe(true);
    expect(messages.map(message => message.id)).toEqual(['delta-b', 'delta-a']);
    expect(messages.every(message => typeof message.updated_at === 'string')).toBe(true);
  });

  it('includes a full cursor without has_more on every empty or offset-past-total path', async () => {
    const paths: [Record<string, string>, string, number][] = [
      [{}, EMPTY_TOKEN, 0], [{ agent: AGENTS[2] }, TOKEN, 0], [{ agent: 'missing' }, TOKEN, 0],
      [{ search: 'missing' }, TOKEN, 0], [{ direction: 'all', offset: '4' }, TOKEN, 4],
      [{ direction: 'all', offset: '100' }, TOKEN, 4],
    ];
    for (const [params, token, total] of paths) {
      const page = await (await request(params, token)).json() as Page;
      expect(page).toEqual({ messages: [], total, cursor: expect.any(String) });
      expect(validMessageCursor(page.cursor!)).toBe(true);
    }
  });

  it('returns a write after a full fetch in a delta starting from its cursor', async () => {
    await env.DB.prepare(
      `INSERT INTO messages (id, agent_id, direction, mode, channel, body)
        VALUES ('delta-bootstrap', ?, 'agent_to_boss', 'async', 'api', 'Before full fetch')`
    ).bind(AGENTS[0]).run();
    const full = await (await request({ direction: 'all' })).json() as Page;
    expect(validMessageCursor(full.cursor!)).toBe(true);
    await env.DB.prepare(
      "UPDATE messages SET body = 'Edited after full fetch' WHERE id = 'delta-bootstrap'"
    ).run();
    const page = await delta({ updated_after: full.cursor! });
    expect(page.messages.find(message => message.id === 'delta-bootstrap')).toMatchObject({
      body: 'Edited after full fetch', updated_at: expect.any(String),
    });
    expect(page.messages.every(message => message.updated_at >= full.cursor!)).toBe(true);
    await env.DB.prepare("DELETE FROM messages WHERE id = 'delta-bootstrap'").run();
  });

  it('includes updated_at in message details and every reply', async () => {
    const message = await testJson(200, testRequest('GET', 'https://test.local/api/boss/messages/delta-old',
      { Authorization: `Bearer ${TOKEN}` })) as MessageResponse;
    expect(message.updated_at).toBe('2026-01-02 03:04:04');
    expect(message.replies?.map(reply => reply.updated_at)).toEqual([CURSOR]);
  });
});
