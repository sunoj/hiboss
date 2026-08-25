// Tests for GET /api/boss/home — iOS Home tab aggregate.
// Covers empty scope, project derivation, activity delta null, and attention ordering.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const BOSS_TOKEN = 'hb_boss_home_00112233445566778899aabb';
const EMPTY_TOKEN = 'hb_boss_home_empty_11223344556677889900';
const AGENT_ID = 'home-agent-1';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS progress_posts (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    agent_id TEXT NOT NULL,
    session_id TEXT,
    project TEXT NOT NULL,
    body TEXT NOT NULL,
    media TEXT NOT NULL DEFAULT '[]',
    tags TEXT NOT NULL DEFAULT '[]',
    agent_label TEXT,
    model TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();

  await env.DB.prepare(
    "INSERT INTO api_keys (id, name, key_hash) VALUES (?, 'home-agent', ?)",
  ).bind(AGENT_ID, await hashApiKey('hb_home_agent_key')).run();

  const boss = await env.DB
    .prepare('INSERT INTO bosses (name, role, token_hash) VALUES (?, ?, ?) RETURNING id')
    .bind('Home Boss', 'viewer', await hashApiKey(BOSS_TOKEN))
    .first<{ id: string }>();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(boss!.id, AGENT_ID).run();

  await env.DB
    .prepare('INSERT INTO bosses (name, role, token_hash) VALUES (?, ?, ?)')
    .bind('Empty Home Boss', 'viewer', await hashApiKey(EMPTY_TOKEN)).run();

  // Live sessions: label prefix → project; waiting + blocked for attention tiers.
  await env.DB.prepare(
    "INSERT INTO sessions (id, agent_id, label, status, status_text) VALUES (?, ?, 'hiboss/main', 'waiting', 'Awaiting boss reply')",
  ).bind('home-sess-wait', AGENT_ID).run();
  await env.DB.prepare(
    "INSERT INTO sessions (id, agent_id, label, status, status_text) VALUES (?, ?, 'smart-router/feat', 'working', 'building')",
  ).bind('home-sess-work', AGENT_ID).run();
  await env.DB.prepare(
    "INSERT INTO sessions (id, agent_id, label, status, status_text) VALUES (?, ?, 'hiboss/blocked', 'blocked', 'Needs input')",
  ).bind('home-sess-block', AGENT_ID).run();

  // Progress-only project (no session label) + post under hiboss.
  await env.DB.prepare(
    "INSERT INTO progress_posts (id, agent_id, project, body, created_at) VALUES (?, ?, 'solo-proj', 'Only from progress', datetime('now'))",
  ).bind('home-post-solo', AGENT_ID).run();
  await env.DB.prepare(
    "INSERT INTO progress_posts (id, agent_id, project, body, created_at) VALUES (?, ?, 'hiboss', 'Shipped home API', datetime('now'))",
  ).bind('home-post-hb', AGENT_ID).run();

  // Blocking critical decision (older) and async high decision (newer) for attention order.
  const soon = new Date(Date.now() + 10 * 60 * 1000).toISOString();
  const older = new Date(Date.now() - 60_000).toISOString().replace('T', ' ').slice(0, 19);
  const newer = new Date().toISOString().replace('T', ' ').slice(0, 19);
  await env.DB.prepare(
    `INSERT INTO messages (id, agent_id, session_id, direction, mode, channel, body, status, priority, metadata, expires_at, created_at)
     VALUES (?, ?, ?, 'agent_to_boss', 'blocking', 'api', 'Block me?', 'delivered', 'critical', ?, ?, ?)`,
  ).bind('home-dec-block', AGENT_ID, 'home-sess-wait', JSON.stringify({ options: ['Yes', 'No'] }), soon, older).run();
  await env.DB.prepare(
    `INSERT INTO messages (id, agent_id, session_id, direction, mode, channel, body, status, priority, metadata, created_at)
     VALUES (?, ?, ?, 'agent_to_boss', 'async', 'api', 'Pick A or B', 'sent', 'high', ?, ?)`,
  ).bind('home-dec-async', AGENT_ID, 'home-sess-work', JSON.stringify({ options: ['A', 'B'] }), newer).run();
});

function headers(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

describe('GET /api/boss/home', () => {
  it('returns empty shape when boss has no accessible agents', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/home', { headers: headers(EMPTY_TOKEN) });
    expect(res.status).toBe(200);
    const body = await res.json() as {
      boss: { name: string };
      kpis: Record<string, number>;
      activity: { days: unknown[]; delta: Record<string, number | null> };
      projects: unknown[];
      attention: unknown[];
    };
    expect(body.boss.name).toBe('Empty Home Boss');
    expect(body.kpis.activeSessions).toBe(0);
    expect(body.kpis.pendingDecisions).toBe(0);
    expect(body.activity.days).toHaveLength(28);
    expect(body.activity.days.every((d) => (d as { posts: number }).posts === 0)).toBe(true);
    expect(body.activity.delta.posts).toBeNull();
    expect(body.projects).toEqual([]);
    expect(body.attention).toEqual([]);
  });

  it('derives projects from label prefix union progress_posts.project', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/home', { headers: headers(BOSS_TOKEN) });
    expect(res.status).toBe(200);
    const body = await res.json() as {
      projects: { name: string; sessions: Record<string, number>; postCount7d: number; pendingDecisions: number }[];
    };
    const names = body.projects.map((p) => p.name).sort();
    expect(names).toContain('hiboss');
    expect(names).toContain('smart-router');
    expect(names).toContain('solo-proj');
    const hiboss = body.projects.find((p) => p.name === 'hiboss');
    expect(hiboss?.sessions.waiting).toBe(1);
    expect(hiboss?.postCount7d).toBeGreaterThanOrEqual(1);
    expect(hiboss?.pendingDecisions).toBeGreaterThanOrEqual(1);
    const solo = body.projects.find((p) => p.name === 'solo-proj');
    expect(solo?.postCount7d).toBe(1);
    expect(solo?.sessions.working).toBe(0);
  });

  it('sets activity delta null when prior window is 0', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/home', { headers: headers(BOSS_TOKEN) });
    const body = await res.json() as {
      activity: { days: { date: string; posts: number; decisions: number; messages: number }[];
        delta: { posts: number | null; decisions: number | null; messages: number | null } };
    };
    expect(body.activity.days).toHaveLength(28);
    // Seed data is all "now" → prior 7d sums are 0 → each delta field null.
    expect(body.activity.delta.posts).toBeNull();
    expect(body.activity.delta.decisions).toBeNull();
    expect(body.activity.delta.messages).toBeNull();
    const last = body.activity.days[27];
    expect(last.posts).toBeGreaterThanOrEqual(1);
    expect(last.decisions).toBeGreaterThanOrEqual(1);
    expect(last.messages).toBeGreaterThanOrEqual(1);
  });

  it('orders attention: blocking decisions, blocked sessions, other decisions, waiting', async () => {
    const res = await SELF.fetch('http://localhost/api/boss/home', { headers: headers(BOSS_TOKEN) });
    const body = await res.json() as {
      attention: { kind: string; messageId?: string; sessionId?: string; mode?: string; status?: string }[];
    };
    expect(body.attention.length).toBeGreaterThanOrEqual(4);
    const keys = body.attention.map((a) =>
      a.kind === 'decision' ? `d:${a.messageId}` : `s:${a.sessionId}:${a.status}`);
    const blockDec = keys.indexOf('d:home-dec-block');
    const blockedSess = keys.indexOf('s:home-sess-block:blocked');
    const asyncDec = keys.indexOf('d:home-dec-async');
    const waitSess = keys.indexOf('s:home-sess-wait:waiting');
    expect(blockDec).toBeGreaterThanOrEqual(0);
    expect(blockedSess).toBeGreaterThan(blockDec);
    expect(asyncDec).toBeGreaterThan(blockedSess);
    expect(waitSess).toBeGreaterThan(asyncDec);
  });
});
