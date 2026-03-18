// Tests for /api/bosses CRUD, access management, preferences, and token generation.
// Covers create, get, update, delete, grant/revoke access, token issuance.
// Depends on cloudflare:test, test-helpers, and the Hono app.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

beforeAll(async () => {
  await seedDatabase();
  const adminTokenHash = await hashApiKey('hb_boss_test_admin_token_0001');
  await env.DB
    .prepare('INSERT INTO bosses (name, role, token_hash) VALUES (?, ?, ?)')
    .bind('Boss Admin', 'admin', adminTokenHash)
    .run();
  const viewerTokenHash = await hashApiKey('hb_boss_test_viewer_token_0001');
  await env.DB
    .prepare('INSERT INTO bosses (name, role, token_hash) VALUES (?, ?, ?)')
    .bind('Boss Viewer', 'viewer', viewerTokenHash)
    .run();
});

let createdBossId: string;

function adminHeaders(): Record<string, string> {
  return {
    Authorization: 'Bearer hb_boss_test_admin_token_0001',
    'Content-Type': 'application/json',
  };
}

function viewerHeaders(): Record<string, string> {
  return {
    Authorization: 'Bearer hb_boss_test_viewer_token_0001',
    'Content-Type': 'application/json',
  };
}

describe('POST /api/bosses', () => {
  it('rejects agent tokens', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ name: 'Agent Rejected' }),
    });
    expect(res.status).toBe(401);
  });

  it('creates a boss with defaults', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses', {
      method: 'POST',
      headers: adminHeaders(),
      body: JSON.stringify({ name: 'Test Boss' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.id).toBeTruthy();
    expect(data.name).toBe('Test Boss');
    expect(data.role).toBe('admin');
    createdBossId = data.id;
  });

  it('creates a boss with explicit role and telegram ID', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses', {
      method: 'POST',
      headers: adminHeaders(),
      body: JSON.stringify({ name: 'Viewer Boss', role: 'viewer', telegram_user_id: '12345' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.role).toBe('viewer');
    expect(data.telegram_user_id).toBe('12345');
  });

  it('rejects empty name', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses', {
      method: 'POST',
      headers: adminHeaders(),
      body: JSON.stringify({ name: '' }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects non-admin bosses', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses', {
      method: 'POST',
      headers: viewerHeaders(),
      body: JSON.stringify({ name: 'Forbidden Boss' }),
    });
    expect(res.status).toBe(403);
  });

  it('defaults invalid role to admin', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses', {
      method: 'POST',
      headers: adminHeaders(),
      body: JSON.stringify({ name: 'Invalid Role', role: 'superadmin' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.role).toBe('admin');
  });
});

describe('GET /api/bosses', () => {
  it('lists all bosses for authenticated bosses', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses', { headers: viewerHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.bosses).toBeInstanceOf(Array);
    expect(data.bosses.length).toBeGreaterThanOrEqual(2);
  });
});

describe('GET /api/bosses/:id', () => {
  it('returns boss by full ID', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, { headers: viewerHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.id).toBe(createdBossId);
    expect(data.agents).toBeInstanceOf(Array);
  });

  it('supports short ID prefix', async () => {
    const prefix = createdBossId.slice(0, 8);
    const res = await SELF.fetch(`http://localhost/api/bosses/${prefix}`, { headers: viewerHeaders() });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.id).toBe(createdBossId);
  });

  it('returns 404 for unknown boss', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses/nonexistent', { headers: viewerHeaders() });
    expect(res.status).toBe(404);
  });
});

describe('PATCH /api/bosses/:id', () => {
  it('updates boss name', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ name: 'Updated Boss' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.name).toBe('Updated Boss');
  });

  it('updates role', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ role: 'manager' }),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.role).toBe('manager');
  });

  it('rejects invalid role', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ role: 'superadmin' }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects empty name', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ name: '  ' }),
    });
    expect(res.status).toBe(400);
  });

  it('sets and merges preferences', async () => {
    const res1 = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { preferred_channel: 'telegram' } }),
    });
    expect(res1.status).toBe(200);
    // Merge additional preference
    const res2 = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { quiet_hours: { start: '22:00', end: '08:00' } } }),
    });
    expect(res2.status).toBe(200);
    // Verify merge
    const getRes = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, { headers: viewerHeaders() });
    const data = await getRes.json() as any;
    expect(data.preferences.preferred_channel).toBe('telegram');
    expect(data.preferences.quiet_hours.start).toBe('22:00');
  });

  it('rejects invalid preferred_channel', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { preferred_channel: 'slack' } }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects invalid notify_priorities', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: { notify_priorities: ['invalid'] } }),
    });
    expect(res.status).toBe(400);
  });

  it('clears preferences with null', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ preferences: null }),
    });
    expect(res.status).toBe(200);
  });

  it('rejects no valid fields', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: adminHeaders(),
      body: JSON.stringify({ unknown_field: 'value' }),
    });
    expect(res.status).toBe(400);
  });

  it('rejects non-admin bosses', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'PATCH',
      headers: viewerHeaders(),
      body: JSON.stringify({ name: 'Forbidden Update' }),
    });
    expect(res.status).toBe(403);
  });
});

describe('Boss access management', () => {
  it('grants agent access', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}/access`, {
      method: 'POST',
      headers: adminHeaders(),
      body: JSON.stringify({ agent_id: 'test-agent-id' }),
    });
    expect(res.status).toBe(201);
  });

  it('rejects grant without agent_id', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}/access`, {
      method: 'POST',
      headers: adminHeaders(),
      body: JSON.stringify({}),
    });
    expect(res.status).toBe(400);
  });

  it('revokes agent access', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}/access/test-agent-id`, {
      method: 'DELETE',
      headers: adminHeaders(),
    });
    expect(res.status).toBe(200);
  });

  it('returns 404 revoking non-existent access', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}/access/nonexistent`, {
      method: 'DELETE',
      headers: adminHeaders(),
    });
    expect(res.status).toBe(404);
  });

  it('rejects non-admin access changes', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}/access`, {
      method: 'POST',
      headers: viewerHeaders(),
      body: JSON.stringify({ agent_id: 'test-agent-id' }),
    });
    expect(res.status).toBe(403);
  });
});

describe('POST /api/bosses/:id/token', () => {
  it('generates a boss auth token', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}/token`, {
      method: 'POST',
      headers: adminHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.token).toMatch(/^hb_boss_/);
    expect(data.id).toBe(createdBossId);
  });

  it('returns 404 for unknown boss', async () => {
    const res = await SELF.fetch('http://localhost/api/bosses/nonexistent/token', {
      method: 'POST',
      headers: adminHeaders(),
    });
    expect(res.status).toBe(404);
  });

  it('rejects non-admin bosses', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}/token`, {
      method: 'POST',
      headers: viewerHeaders(),
    });
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'admin required' });
  });
});

describe('DELETE /api/bosses/:id', () => {
  it('deletes a boss', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'DELETE',
      headers: adminHeaders(),
    });
    expect(res.status).toBe(200);
  });

  it('returns 404 for already deleted boss', async () => {
    const res = await SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, {
      method: 'DELETE',
      headers: adminHeaders(),
    });
    expect(res.status).toBe(404);
  });
});
