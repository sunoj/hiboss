// Tests for /api/sessions endpoints: register, list, heartbeat, delete.
// Covers session CRUD and status management.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

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
});

describe('GET /api/sessions', () => {
  it('lists own sessions', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions', { headers: authHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.sessions).toBeInstanceOf(Array);
    expect(data.sessions.length).toBeGreaterThanOrEqual(1);
  });

  it('lists all agents sessions with ?all=true', async () => {
    const res = await SELF.fetch('http://localhost/api/sessions?all=true', { headers: authHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.sessions).toBeInstanceOf(Array);
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
