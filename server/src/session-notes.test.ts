// Session notes integration coverage for authorization, retries and read state.
// Uses the real Worker and D1 with shared seeded credentials.
import { beforeAll, describe, expect, it } from 'vitest';
import { env, SELF } from 'cloudflare:test';
import { seedDatabase, seedBossToken, authHeaders, createAgentAuth } from './test-helpers';

type Note = { id: string; body: string; status: string; read_at: string | null; boss_name: string };
const bossHeaders = (token: string) => ({
  Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
});
const path = (session = 'note-session') => `/api/boss/sessions/${session}/notes`;
const agentPath = (session = 'note-session') => `/api/sessions/${session}/notes`;
const get = (url: string, headers = authHeaders()) => SELF.fetch(`https://test${url}`, { headers });
const post = (url: string, body: unknown, headers: Record<string, string> = bossHeaders('notes-manager')) =>
  SELF.fetch(`https://test${url}`, { method: 'POST', headers, body: JSON.stringify(body) });

beforeAll(async () => {
  await seedDatabase();
  const manager = await seedBossToken('Boss', 'manager', 'notes-manager');
  const viewer = await seedBossToken('Viewer', 'viewer', 'notes-viewer');
  await createAgentAuth('other-note-agent', 'other-note-key');
  for (const boss of [manager, viewer]) {
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(boss, 'test-agent-id').run();
  }
  for (const [id, agent] of [['note-session', 'test-agent-id'], ['other-session', 'other-note-agent']]) {
    await env.DB.prepare("INSERT INTO sessions (id, agent_id, status) VALUES (?, ?, 'completed')")
      .bind(id, agent).run();
  }
});

describe('session note authorization', () => {
  it('boss writes only accessible exact sessions, including completed sessions', async () => {
    expect((await post(path('other-session'), { body: 'hidden' })).status).toBe(404);
    expect((await post(path('missing'), { body: 'missing' })).status).toBe(404);
    expect((await post(path('note-sess'), { body: 'prefix' })).status).toBe(404);
    expect((await post(path(), { body: '  full body  ' })).status).toBe(201);
  });

  it('boss reads only accessible exact sessions', async () => {
    expect((await get(path('other-session'), bossHeaders('notes-manager'))).status).toBe(404);
    expect((await get(path('note-sess'), bossHeaders('notes-manager'))).status).toBe(404);
    expect((await get(path(), bossHeaders('notes-manager'))).status).toBe(200);
  });

  it('viewers can read but cannot write', async () => {
    expect((await post(path(), { body: 'denied' }, bossHeaders('notes-viewer'))).status).toBe(403);
    expect((await get(path(), bossHeaders('notes-viewer'))).status).toBe(200);
  });

  it('agents can list and mark only their own session', async () => {
    const created = await post(path(), { body: 'private' });
    const note = await created.json<Note>();
    const other = bossHeaders('other-note-key');
    expect((await get(agentPath(), other)).status).toBe(404);
    expect((await post(`${agentPath()}/read`, { ids: [note.id] }, other)).status).toBe(404);
    expect((await get(agentPath('note-sess'))).status).toBe(404);
    const unchanged = await env.DB.prepare('SELECT status FROM session_notes WHERE id = ?')
      .bind(note.id).first<{ status: string }>();
    expect(unchanged?.status).toBe('pending');
    expect((await get(agentPath(), bossHeaders('notes-manager'))).status).toBe(401);
  });
});

describe('session note contract', () => {
  it('validates body and ids, including malformed JSON', async () => {
    for (const body of ['', '  ', 'x'.repeat(4001), 3, null]) {
      expect((await post(path(), { body })).status).toBe(400);
    }
    expect((await post(path(), null)).status).toBe(400);
    expect((await SELF.fetch(`https://test${path()}`, {
      method: 'POST', headers: bossHeaders('notes-manager'), body: '{',
    })).status).toBe(400);
    for (const ids of [[], ['x', 4], Array(51).fill('x'), null]) {
      expect((await post(`${agentPath()}/read`, { ids }, authHeaders())).status).toBe(400);
    }
    expect((await get(`${agentPath()}?status=bad`)).status).toBe(400);
  });

  it('retries return the original note and keys are scoped to session and boss', async () => {
    const headers = { ...bossHeaders('notes-manager'), 'Idempotency-Key': 'retry' };
    const first = await post(path(), { body: 'original' }, headers);
    expect(first.status).toBe(201);
    const note = await first.json<Note>();
    const retry = await post(path(), { body: 'changed' }, headers);
    expect(retry.status).toBe(200);
    expect(await retry.json()).toEqual(note);
    const admin = await seedBossToken('Admin', 'admin', 'notes-admin');
    expect(admin).toBeTruthy();
    expect((await post(path(), { body: 'another boss' }, {
      ...bossHeaders('notes-admin'), 'Idempotency-Key': 'retry',
    })).status).toBe(201);
    expect((await post(path('other-session'), { body: 'another session' }, {
      ...bossHeaders('notes-admin'), 'Idempotency-Key': 'retry',
    })).status).toBe(201);
    expect((await post(path(), { body: 'same key another session' }, {
      ...bossHeaders('notes-admin'), 'Idempotency-Key': 'retry',
    })).status).toBe(200);
  });

  it('marks pending notes once, scopes ids, and exposes read timestamps', async () => {
    const note = await (await post(path(), { body: '  read me  ' })).json<Note>();
    expect(note.body).toBe('read me');
    expect(note.boss_name).toBe('Boss');
    expect(note.read_at).toBeNull();
    expect(await (await post(`${agentPath('other-session')}/read`, { ids: [note.id] },
      bossHeaders('other-note-key'))).json()).toEqual({ read: 0 });
    for (const count of [1, 0]) {
      expect(await (await post(`${agentPath()}/read`, { ids: [note.id, note.id] }, authHeaders()))
        .json()).toEqual({ read: count });
    }
    const pending = await (await get(agentPath())).json<{ notes: Note[] }>();
    expect(pending.notes.some(n => n.id === note.id)).toBe(false);
    const all = await (await get(`${agentPath()}?status=all`)).json<{ notes: Note[] }>();
    const read = all.notes.find(n => n.id === note.id);
    expect(read?.status).toBe('read');
    expect(read?.read_at).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  });

  it('atomic concurrent retries create one note and no delivery side effects', async () => {
    const before = await env.DB.prepare('SELECT COUNT(*) AS n FROM messages').first<{ n: number }>();
    const headers = { ...bossHeaders('notes-manager'), 'Idempotency-Key': 'concurrent' };
    const responses = await Promise.all([1, 2].map(() => post(path(), { body: 'once' }, headers)));
    expect(responses.map(r => r.status).sort()).toEqual([200, 201]);
    const [first, second] = await Promise.all(responses.map(r => r.json<Note>()));
    expect(first).toEqual(second);
    const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM session_notes WHERE body = ?')
      .bind('once').first<{ n: number }>();
    expect(count?.n).toBe(1);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM messages').first()).toEqual(before);
  });

  it('deregistering a note-bearing session retains its completed history', async () => {
    await post(path(), { body: 'retain' });
    const result = await SELF.fetch('https://test/api/sessions/note-session', {
      method: 'DELETE', headers: authHeaders(),
    });
    expect(result.status).toBe(200);
    expect((await get(path(), bossHeaders('notes-manager'))).status).toBe(200);
    expect(await env.DB.prepare('SELECT status FROM sessions WHERE id = ?')
      .bind('note-session').first()).toEqual({ status: 'completed' });
  });

  it('orders history and caps boss results without truncating agent pending results', async () => {
    await env.DB.batch(Array.from({ length: 52 }, (_, i) => env.DB.prepare(
      `INSERT INTO session_notes (id, session_id, agent_id, boss_id, body, created_at)
       SELECT ?, 'note-session', 'test-agent-id', id, ?, ? FROM bosses WHERE name = 'Boss'`,
    ).bind(`ordered-${i}`, `body-${i}`, `2099-01-01 00:00:${String(i).padStart(2, '0')}`)));
    const boss = await (await get(path(), bossHeaders('notes-manager'))).json<{ notes: Note[] }>();
    expect(boss.notes).toHaveLength(50);
    expect(boss.notes[0].id).toBe('ordered-51');
    const agent = await (await get(agentPath())).json<{ notes: Note[] }>();
    expect(agent.notes.length).toBeGreaterThanOrEqual(52);
    expect(agent.notes.at(-1)?.id).toBe('ordered-51');
    expect(agent.notes.findIndex(n => n.id === 'ordered-0'))
      .toBeLessThan(agent.notes.findIndex(n => n.id === 'ordered-1'));
  });
});
