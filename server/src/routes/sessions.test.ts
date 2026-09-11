// Tests for /api/sessions endpoints: register, list, heartbeat, delete.
// Covers session CRUD and status management.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId, seedBossToken } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

beforeAll(async () => {
  await seedDatabase();
  const otherAgentKeyHash = await hashApiKey('hb_test_key_1111111111111111');
  await env.DB
    .prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('test-agent-id-2', 'test-agent-2', otherAgentKeyHash)
    .run();
  await seedBossToken('Sessions Boss', 'admin', 'hb_boss_sessions_token_0001');
});

function otherAgentHeaders(): Record<string, string> {
  return {
    Authorization: 'Bearer hb_test_key_1111111111111111',
    'Content-Type': 'application/json',
  };
}

function bossHeaders(): Record<string, string> {
  return {
    Authorization: 'Bearer hb_boss_sessions_token_0001',
    'Content-Type': 'application/json',
  };
}

describe('POST /api/sessions', () => {
  it('registers a session with ID only', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ id: 'sess-test-1' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.id).toBe('sess-test-1');
    expect(data.status).toBe('working');
  });

  it('registers with branch, cwd, label, and status', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({
        id: 'sess-test-2',
        branch: 'feat/test',
        cwd: '/home/user/project',
        label: 'test-session',
        status: 'idle',
        status_text: 'Waiting for input',
      }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.branch).toBe('feat/test');
    expect(data.cwd).toBe('/home/user/project');
    expect(data.label).toBe('test-session');
    expect(data.status).toBe('idle');
    expect(data.status_text).toBe('Waiting for input');
  });
});

describe('POST /api/sessions validation', () => {
  it('defaults invalid status to working', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ id: 'sess-test-3', status: 'invalid' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.status).toBe('working');
  });

  it('rejects missing id', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
  });
});

describe('POST /api/sessions ownership and updates', () => {
  it('upserts on conflict (re-register same ID)', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ id: 'sess-test-1', status: 'blocked', status_text: 'Need help' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.status).toBe('blocked');
  });

  it('auto-generates label from cwd and branch', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ id: 'sess-test-4', cwd: '/project', branch: 'main' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.label).toBe('/project/main');
  });

  it('rejects cross-agent overwrites', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: otherAgentHeaders(),
      body: JSON.stringify({ id: 'sess-test-1', status: 'idle' }),
    });
    expect(res.status).toBe(409);
    expect(await res.text()).toBe('session belongs to another agent');
  });
});

describe('GET /api/sessions', () => {
  it('lists own sessions', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', { headers: authHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.sessions).toBeInstanceOf(Array);
    expect(data.sessions.length).toBeGreaterThanOrEqual(1);
  });

  it('ignores ?all=true for agent callers', async () => {
    await SELF.fetch('http://localhost/api/sessions', {
      method: 'POST',
      headers: otherAgentHeaders(),
      body: JSON.stringify({ id: 'sess-other-agent-1', status: 'idle' }),
    });
    const res = await SELF.fetch('http://localhost/api/sessions?all=true', { headers: authHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.sessions).toBeInstanceOf(Array);
    expect(data.sessions.every((session: any) => session.agent_id === getTestAgentId())).toBe(true);
  });

  it.each(['?all=true', '', '?all=false'])('allows admins to list all recent sessions with %s', async (query) => {
    const res = await SELF.fetch(`http://localhost/api/sessions${query}`, { headers: bossHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as { sessions: { agent_id: string }[] };
    const agentIds = data.sessions.map((session) => session.agent_id);
    expect(agentIds).toContain(getTestAgentId());
    expect(agentIds).toContain('test-agent-id-2');
  });
});

describe('GET /api/sessions boss access', () => {
  it.each(['?all=true', '', '?all=false'])('limits viewers to granted agents with %s', async (query) => {
    const token = `hb_boss_viewer_sessions_${query}`;
    const bossId = await seedBossToken('Session Viewer', 'viewer', token);
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, getTestAgentId()).run();
    await env.DB.prepare("INSERT INTO sessions (id, agent_id, last_seen_at) VALUES (?, ?, datetime('now', '-16 minutes'))")
      .bind(`stale-viewer-${query}`, getTestAgentId()).run();
    const res = await SELF.fetch(`http://localhost/api/sessions${query}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { sessions: { id: string; agent_id: string }[] };
    expect(data.sessions.length).toBeGreaterThan(0);
    expect(data.sessions.every((session) => session.agent_id === getTestAgentId())).toBe(true);
    expect(data.sessions.some((session) => session.id.startsWith('stale-viewer-'))).toBe(false);
  });

  it.each(['?all=true', '', '?all=false'])('returns no sessions for managers without grants with %s', async (query) => {
    const token = `hb_boss_manager_sessions_${query}`;
    await seedBossToken('Session Manager', 'manager', token);
    const res = await SELF.fetch(`http://localhost/api/sessions${query}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ sessions: [] });
  });
});

describe('PATCH /api/sessions/:id', () => {
  it('heartbeats a session', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions/sess-test-1', {
      method: 'PATCH',
      headers: { Authorization: authHeaders().Authorization },
    });
    expect(res.status).toBe(200);
  });

  it('updates status via heartbeat', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions/sess-test-1', {
      method: 'PATCH',
      headers: authHeaders(),
      body: JSON.stringify({ status: 'waiting', status_text: 'Waiting for deploy' }),
    });
    expect(res.status).toBe(200);
  });

  it('returns 404 for unknown session', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions/nonexistent', {
      method: 'PATCH',
      headers: { Authorization: authHeaders().Authorization },
    });
    expect(res.status).toBe(404);
  });
});

describe('DELETE /api/sessions/:id', () => {
  it('deletes a session', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions/sess-test-4', {
      method: 'DELETE',
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
  });
});
