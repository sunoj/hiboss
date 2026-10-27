// Session completion and removal through the real HTTP routes: every completing path expires
// the session's open asks the same way, removal survives panels, boss deletion refuses history.
// Depends on the Worker (SELF), seeded D1, and the panel publish route.

import { testRequest } from './test-request';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from './test-helpers';
import { handleScheduled } from './scheduled';

const ADMIN = 'hb_session_lifecycle_admin_01';
const ADMIN_ID = 'session-lifecycle-admin';
const inHours = (hours: number): string => new Date(Date.now() + hours * 3_600_000).toISOString();
const unique = (name: string): string => `sl-${name}-${crypto.randomUUID().slice(0, 8)}`;

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Session Lifecycle Admin', 'admin', ADMIN, ADMIN_ID);
});

async function ask(id: string, session: string, expires: string | null): Promise<void> {
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status,
    metadata, expires_at, session_id) VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Q?', 'delivered', ?, ?, ?)`)
    .bind(id, getTestAgentId(), JSON.stringify({ options: ['Ship', 'Hold'], default_option: 'Hold' }),
      expires, session).run();
}

async function state(id: string): Promise<{ status: string; replies: number }> {
  const row = await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(id).first<{ status: string }>();
  const replies = await env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE reply_to = ?').bind(id).first<{ n: number }>();
  return { status: row?.status ?? 'missing', replies: replies?.n ?? 0 };
}

function register(session: string, status?: string): Promise<Response> {
  return testRequest('POST', 'http://localhost/api/sessions', authHeaders(),
    { id: session, project: 'session-lifecycle', ...(status ? { status } : {}) });
}

async function publishPanel(session: string, targetBossId = ADMIN_ID): Promise<string> {
  const res = await testRequest('POST', 'https://test.local/api/panels',
    { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() }, {
      protocolVersion: 2, targetBossId, sessionId: session, taskKey: 'lifecycle', title: 'Lifecycle',
      catalogId: 'hiboss.panel', catalogVersion: 1,
      spec: { root: 'metric', elements: { metric: { type: 'Metric', props: { label: 'Done', value: { $state: '/task/done' } }, children: [] } } },
      stateSchema: { type: 'object', properties: { task: { type: 'object', properties: { done: { type: 'integer' } },
        required: ['done'], additionalProperties: false } }, required: ['task'], additionalProperties: false },
      initialState: { task: { done: 0 } },
    });
  expect(res.status).toBe(201);
  return ((await res.json()) as { panelId: string }).panelId;
}

describe('session completion', () => {
  it('POST completed expires a future-deadline ask so the cron never answers it by default', async () => {
    const session = unique('post');
    expect((await register(session)).status).toBe(201);
    const pending = unique('ask');
    await ask(pending, session, inHours(1));
    expect((await register(session, 'completed')).status).toBe(201);
    expect(await state(pending)).toEqual({ status: 'expired', replies: 0 });
    await env.DB.prepare("UPDATE messages SET expires_at = '2000-01-01T00:00:00Z' WHERE id = ?").bind(pending).run();
    await handleScheduled(env);
    expect(await state(pending)).toEqual({ status: 'expired', replies: 0 });
  });

  it('PATCH completed expires every open ask, beyond one batch of 50', async () => {
    const session = unique('many');
    expect((await register(session)).status).toBe(201);
    const ids = Array.from({ length: 60 }, (_, i) => `${session}-ask-${i}`);
    for (const id of ids) await ask(id, session, null);
    const res = await testRequest('PATCH', `http://localhost/api/sessions/${session}`, authHeaders(),
      { status: 'completed' });
    expect(res.status).toBe(200);
    const open = await env.DB.prepare("SELECT COUNT(*) AS n FROM messages WHERE session_id = ? AND status != 'expired'")
      .bind(session).first<{ n: number }>();
    expect(open?.n).toBe(0);
  });
});

describe('session removal with panels', () => {
  it('deregisters a session a panel references, keeping the panel and its session label', async () => {
    const session = unique('panel');
    expect((await register(session)).status).toBe(201);
    const panelId = await publishPanel(session);
    const pending = unique('panel-ask');
    await ask(pending, session, inHours(1));
    const res = await SELF.fetch(`http://localhost/api/sessions/${session}`, { method: 'DELETE', headers: authHeaders() });
    expect(res.status).toBe(200);
    expect(await state(pending)).toEqual({ status: 'expired', replies: 0 });
    const row = await env.DB.prepare('SELECT status, telegram_topic_id FROM sessions WHERE id = ?')
      .bind(session).first<{ status: string; telegram_topic_id: number | null }>();
    expect(row).toEqual({ status: 'completed', telegram_topic_id: null });
    const panel = await SELF.fetch(`https://test.local/api/panels/${panelId}`, { headers: { Authorization: `Bearer ${ADMIN}` } });
    expect(panel.status).toBe(200);
  });

  it('still deletes a session no panel references', async () => {
    const session = unique('bare');
    expect((await register(session)).status).toBe(201);
    const res = await SELF.fetch(`http://localhost/api/sessions/${session}`, { method: 'DELETE', headers: authHeaders() });
    expect(res.status).toBe(200);
    expect(await env.DB.prepare('SELECT id FROM sessions WHERE id = ?').bind(session).first()).toBeNull();
  });
});

describe('boss hard deletion', () => {
  it('refuses with 409 and changes nothing when panels target the boss', async () => {
    const bossId = 'session-lifecycle-target';
    await seedBossToken('Panel Target', 'manager', 'hb_session_lifecycle_target_1', bossId);
    await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, getTestAgentId()).run();
    const session = unique('boss');
    expect((await register(session)).status).toBe(201);
    const panelId = await publishPanel(session, bossId);
    const res = await testRequest('DELETE', `http://localhost/api/bosses/${bossId}`,
      { Authorization: `Bearer ${ADMIN}` });
    expect(res.status).toBe(409);
    expect(await res.text()).toContain('archive');
    expect(await env.DB.prepare('SELECT id FROM bosses WHERE id = ?').bind(bossId).first()).not.toBeNull();
    expect(await env.DB.prepare('SELECT panel_id FROM panels WHERE panel_id = ?').bind(panelId).first()).not.toBeNull();
  });
});
