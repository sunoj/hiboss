// Exercise dashboard lists through authenticated HTTP handlers and real D1.
// Check bounded query plans, exact totals, pagination, and session metadata parity.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import worker from '../index';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { SESSION_LABEL_SQL, mapSessionProject, type SessionProjectRow } from '../projects/session-label';
import { buildFilters, mapMessageRow } from './message-helpers';
import type { MessageRow } from '../types';

const token = `hb_boss_${'cd'.repeat(16)}`;
const narrowToken = `hb_boss_${'ce'.repeat(16)}`;
const agents = Array.from({ length: 13 }, (_, i) => `list-agent-${i.toString().padStart(2, '0')}`);
const placeholders = agents.map(() => '?').join(', ');
interface Query { sql: string; binds: unknown[] }

beforeAll(async () => {
  await seedDatabase();
  const boss = await seedBossToken('List reader', 'manager', token);
  const narrow = await seedBossToken('Narrow list reader', 'manager', narrowToken);
  for (const id of agents) {
    await env.DB.prepare('INSERT INTO api_keys (id, name) VALUES (?, ?)').bind(id, id).run();
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, id).run();
    if (id.endsWith('11') || id.endsWith('12')) {
      await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(narrow, id).run();
    }
  }
  await env.DB.prepare("INSERT INTO projects (id, slug, display_name) VALUES ('list-project', 'canonical', 'Canonical project')").run();
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<80)
    INSERT INTO sessions (id, agent_id, project_id, label, branch, last_seen_at)
    SELECT 'list-session-'||x, printf('list-agent-%02d', x%13), CASE WHEN x%5=0 THEN NULL ELSE 'list-project' END,
      CASE WHEN x%4=0 THEN NULL ELSE 'old/topic/sub' END, CASE WHEN x%3=0 THEN '' WHEN x%3=1 THEN 'explicit' ELSE NULL END,
      datetime('now', CASE WHEN x<40 THEN '-1 minute' ELSE '-1 day' END) FROM n`).run();
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<259)
    INSERT INTO messages (id, agent_id, session_id, direction, mode, body, status, priority, created_at)
    SELECT 'list-message-'||x, printf('list-agent-%02d', x%13), CASE WHEN x%7=0 THEN NULL ELSE 'list-session-'||(x%81) END,
      CASE WHEN x%3=0 THEN 'boss_to_agent' ELSE 'agent_to_boss' END, 'async', 'search '||x,
      CASE WHEN x%2=0 THEN 'sent' ELSE 'read' END, CASE WHEN x%4=0 THEN 'high' ELSE 'normal' END,
      datetime('2026-01-01', '+'||(x/26)||' seconds') FROM n`).run();
  await env.DB.prepare("INSERT INTO messages (id, agent_id, direction, mode, body) VALUES ('hidden-list-message', ?, 'agent_to_boss', 'async', 'hidden')")
    .bind(getTestAgentId()).run();
  await env.DB.prepare(`WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<30043)
    INSERT INTO messages (id, agent_id, direction, mode, body, created_at)
    SELECT 'large-agent-'||x, ?, 'agent_to_boss', 'async', 'hidden', '2027-01-01 00:00:00' FROM n`)
    .bind(getTestAgentId()).run();
});

async function request(path: string, headers: Record<string, string> = { Authorization: `Bearer ${token}` }) {
  const queries: Query[] = [];
  const wrap = (statement: D1PreparedStatement, sql: string, binds: unknown[]): D1PreparedStatement => new Proxy(statement, {
    get(target, property) {
      if (property === 'bind') return (...values: unknown[]) => wrap(target.bind(...values), sql, values);
      if (property === 'all' || property === 'first') return (...args: []) => {
        queries.push({ sql, binds });
        return target[property](...args);
      };
      const value = Reflect.get(target, property);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  const DB = new Proxy(env.DB, {
    get(target, property) {
      if (property === 'prepare') return (sql: string) => wrap(target.prepare(sql), sql, []);
      const value = Reflect.get(target, property);
      return typeof value === 'function' ? value.bind(target) : value;
    },
  });
  const ctx = createExecutionContext();
  const response = await worker.fetch(new Request(`http://localhost${path}`, { headers }), { ...env, DB }, ctx);
  await waitOnExecutionContext(ctx);
  expect(response.status).toBe(200);
  return { response, queries };
}

async function plan(query: Query): Promise<string[]> {
  const result = await env.DB.prepare(`EXPLAIN QUERY PLAN ${query.sql}`).bind(...query.binds).all<{ detail: string }>();
  return result.results.map(row => row.detail);
}

it.each([
  ['?direction=all', 'idx_messages_agent_page'],
  ['', 'idx_messages_boss_page'],
])('streams the broad message page through the ordered index: %s', async (suffix, index) => {
  const { queries } = await request(`/api/boss/messages${suffix}`);
  const query = queries.find(query => query.sql.startsWith('SELECT messages.*'))!;
  const details = await plan(query);
  expect(details.some(detail => detail.includes(`SEARCH messages USING INDEX ${index}`))).toBe(true);
  expect(query.sql).toMatch(/ORDER BY created_at DESC, id DESC LIMIT \? OFFSET \?\) messages/);
  const result = await env.DB.prepare(query.sql).bind(...query.binds).all();
  expect(result.meta.rows_read).toBeLessThan(13 * 21 + 40);
});

it.each([
  ['direction=all', '', []],
  ['', " AND direction = 'agent_to_boss'", []],
  ['unread=true', " AND direction = 'agent_to_boss' AND status IN ('sent', 'delivered')", []],
  ['priority=high', " AND direction = 'agent_to_boss' AND priority IN (?)", ['high']],
  ['search=search%201', " AND direction = 'agent_to_boss' AND body LIKE ?", ['%search 1%']],
  ['session=list-session-2', " AND direction = 'agent_to_boss' AND session_id = ?", ['list-session-2']],
])('keeps full message rows, ties, offsets and exact totals: %s', async (params, filter, binds) => {
  for (const offset of [0, 17, 250, 1000]) {
    const { response } = await request(`/api/boss/messages?${params}&limit=17&offset=${offset}`);
    const actual = await response.json() as { messages: MessageRow[]; total: number };
    const where = `agent_id IN (${placeholders})${filter}`;
    const legacy = await env.DB.prepare(`SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label,
      sessions.branch AS session_branch, sessions.status AS session_status FROM (SELECT * FROM messages WHERE ${where}) messages
      LEFT JOIN api_keys ON api_keys.id = messages.agent_id LEFT JOIN sessions ON sessions.id = messages.session_id
      ORDER BY messages.created_at DESC, messages.id DESC LIMIT ? OFFSET ?`).bind(...agents, ...binds, 17, offset).all<MessageRow>();
    const count = await env.DB.prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`).bind(...agents, ...binds).first<{ total: number }>();
    expect(actual).toEqual({ messages: legacy.results.map(mapMessageRow), total: count?.total });
  }
});

it('keeps agent message visibility and joins only after pagination', async () => {
  const { response, queries } = await request('/api/messages?limit=1', authHeaders());
  const query = queries.find(query => query.sql.startsWith('SELECT messages.*'))!;
  expect(query.sql).toMatch(/LIMIT \? OFFSET \?\) messages LEFT JOIN/);
  expect((await plan(query)).some(detail => detail.includes('CO-ROUTINE messages'))).toBe(true);
  const { where, binds } = buildFilters(getTestAgentId(), null, null);
  const count = await env.DB.prepare(`SELECT COUNT(*) AS total FROM messages WHERE ${where}`).bind(...binds).first<{ total: number }>();
  const actual = await response.json() as { messages: MessageRow[]; total: number };
  expect(actual.total).toBe(count?.total);
  const legacy = await env.DB.prepare(`SELECT messages.*, api_keys.name AS agent_name, sessions.label AS session_label,
    sessions.branch AS session_branch, sessions.status AS session_status FROM (SELECT * FROM messages WHERE ${where}) messages
    LEFT JOIN api_keys ON api_keys.id = messages.agent_id LEFT JOIN sessions ON sessions.id = messages.session_id
    ORDER BY messages.created_at DESC, messages.id DESC LIMIT 1`).bind(...binds).all<MessageRow>();
  expect(actual.messages).toEqual(legacy.results.map(mapMessageRow));
});

it.each([false, true])('keeps session rows and labels, include_inactive=%s', async (inactive) => {
  const { response, queries } = await request(`/api/boss/sessions?include_inactive=${inactive}`);
  const query = queries.find(query => query.sql.startsWith('SELECT s.*'))!;
  const details = await plan(query);
  expect(details.some(detail => detail.includes('idx_sessions_agent'))).toBe(true);
  expect(query.sql).not.toContain('INDEXED BY');
  expect(query.sql).not.toContain('JOIN');
  const legacy = await env.DB.prepare(`SELECT s.*, api_keys.name AS agent_name, p.slug AS project_slug,
    p.display_name AS project_display_name, ${SESSION_LABEL_SQL} AS label FROM sessions s
    LEFT JOIN projects p ON p.id = s.project_id LEFT JOIN api_keys ON api_keys.id = s.agent_id
    WHERE s.agent_id IN (${placeholders}) ${inactive ? '' : "AND s.last_seen_at > datetime('now', '-15 minutes')"}
    ORDER BY s.last_seen_at DESC`).bind(...agents).all<SessionProjectRow>();
  expect(await response.json()).toEqual({ sessions: legacy.results.map(mapSessionProject) });
});

it('keeps inaccessible-agent filters empty', async () => {
  const { response } = await request(`/api/boss/messages?agent=${getTestAgentId()}`);
  expect(await response.json()).toEqual({ messages: [], total: 0 });
});

it.each(['all', 'default'])('bounds narrow-access reads including offsets at and past total: %s', async (direction) => {
  const headers = { Authorization: `Bearer ${narrowToken}` };
  const directionQuery = direction === 'all' ? 'direction=all&' : '';
  const filter = direction === 'all' ? '' : " AND direction = 'agent_to_boss'";
  const count = await env.DB.prepare(`SELECT COUNT(*) AS total FROM messages WHERE agent_id IN (?, ?)${filter}`)
    .bind(agents[11], agents[12]).first<{ total: number }>();
  const total = count?.total ?? 0;
  for (const offset of [0, total, total + 1000]) {
    const { response, queries } = await request(`/api/boss/messages?${directionQuery}limit=10&offset=${offset}`, headers);
    const actual = await response.json() as { messages: MessageRow[]; total: number };
    expect(actual.total).toBe(total);
    const page = queries.find(query => query.sql.startsWith('SELECT messages.*'));
    if (offset >= total) {
      expect(page).toBeUndefined();
      expect(actual.messages).toEqual([]);
    } else {
      expect(page).toBeDefined();
      const result = await env.DB.prepare(page!.sql).bind(...page!.binds).all();
      expect(result.meta.rows_read).toBeLessThanOrEqual(2 * 2 * 11 + 3 * 10);
      expect(actual.messages.every(row => row.agent_id === agents[11] || row.agent_id === agents[12])).toBe(true);
    }
  }
});
