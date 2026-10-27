// Tests for /api/bosses CRUD, access management, preferences, and token generation.
// Covers create, get, update, delete, grant/revoke access, token issuance.
// Depends on cloudflare:test, test-helpers, and the Hono app.
import { testRequest } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, seedBossToken } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Boss Admin', 'admin', 'hb_boss_test_admin_token_0001');
  await seedBossToken('Boss Viewer', 'viewer', 'hb_boss_test_viewer_token_0001');
});

let createdBossId: string;
let generatedToken: string;
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
    const res = await testRequest('POST', 'http://localhost/api/bosses', authHeaders(),
      { name: 'Agent Rejected' });
    expect(res.status).toBe(401);
  });

  it('creates a boss with defaults', async () => {
    const res = await testRequest('POST', 'http://localhost/api/bosses', adminHeaders(),
      { name: 'Test Boss' });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.id).toBeTruthy();
    expect(data.name).toBe('Test Boss');
    expect(data.role).toBe('admin');
    createdBossId = data.id;
  });

  it('creates a boss with explicit role and telegram ID', async () => {
    const res = await testRequest('POST', 'http://localhost/api/bosses', adminHeaders(),
      { name: 'Viewer Boss', role: 'viewer', telegram_user_id: '12345' });
    expect(res.status).toBe(201);
    const data = await res.json() as any;
    expect(data.role).toBe('viewer');
    expect(data.telegram_user_id).toBe('12345');
  });

  it('rejects empty name', async () => {
    const res = await testRequest('POST', 'http://localhost/api/bosses', adminHeaders(), { name: '' });
    expect(res.status).toBe(400);
  });

  it('rejects non-admin bosses', async () => {
    const res = await testRequest('POST', 'http://localhost/api/bosses', viewerHeaders(),
      { name: 'Forbidden Boss' });
    expect(res.status).toBe(403);
  });

  it('defaults invalid role to admin', async () => {
    const res = await testRequest('POST', 'http://localhost/api/bosses', adminHeaders(),
      { name: 'Invalid Role', role: 'superadmin' });
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
    const res = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { name: 'Updated Boss' });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.name).toBe('Updated Boss');
  });

  it('updates role', async () => {
    const res = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { role: 'manager' });
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.role).toBe('manager');
  });

  it('rejects invalid role', async () => {
    const res = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { role: 'superadmin' });
    expect(res.status).toBe(400);
  });

  it('rejects empty name', async () => {
    const res = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { name: '  ' });
    expect(res.status).toBe(400);
  });

  it('rejects no valid fields', async () => {
    const res = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { unknown_field: 'value' });
    expect(res.status).toBe(400);
  });

  it('rejects non-admin bosses', async () => {
    const res = await testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, viewerHeaders(),
      { name: 'Forbidden Update' });
    expect(res.status).toBe(403);
  });
});

describe('Boss access management', () => {
  it('grants agent access', async () => {
    const res = await testRequest('POST', `http://localhost/api/bosses/${createdBossId}/access`,
      adminHeaders(), { agent_id: 'test-agent-id' });
    expect(res.status).toBe(201);
  });

  it('rejects grant without agent_id', async () => {
    const res = await testRequest('POST', `http://localhost/api/bosses/${createdBossId}/access`,
      adminHeaders(), {});
    expect(res.status).toBe(400);
  });

  it('revokes agent access', async () => {
    const res = await testRequest('DELETE',
      `http://localhost/api/bosses/${createdBossId}/access/test-agent-id`, adminHeaders());
    expect(res.status).toBe(200);
  });

  it('returns 404 revoking non-existent access', async () => {
    const res = await testRequest('DELETE',
      `http://localhost/api/bosses/${createdBossId}/access/nonexistent`, adminHeaders());
    expect(res.status).toBe(404);
  });

  it('rejects non-admin access changes', async () => {
    const res = await testRequest('POST', `http://localhost/api/bosses/${createdBossId}/access`,
      viewerHeaders(), { agent_id: 'test-agent-id' });
    expect(res.status).toBe(403);
  });
});

describe('POST /api/bosses/:id/token', () => {
  it('generates a boss auth token', async () => {
    const res = await testRequest('POST', `http://localhost/api/bosses/${createdBossId}/token`,
      adminHeaders());
    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.token).toMatch(/^hb_boss_/);
    expect(data.id).toBe(createdBossId);
    generatedToken = data.token;
  });

  it('revokes the prior target token when rotating', async () => {
    const res = await testRequest('POST', `http://localhost/api/bosses/${createdBossId}/token`,
      adminHeaders());
    expect(res.status).toBe(200);
    const data = await res.json() as { token: string };
    expect((await testRequest('GET', 'http://localhost/api/boss/me',
      { Authorization: `Bearer ${generatedToken}` })).status).toBe(401);
    expect((await testRequest('GET', 'http://localhost/api/boss/me',
      { Authorization: `Bearer ${data.token}` })).status).toBe(200);
    const live = await env.DB.prepare('SELECT token_hash FROM boss_tokens WHERE boss_id = ? AND revoked_at IS NULL')
      .bind(createdBossId).all<{ token_hash: string }>();
    expect(live.results).toHaveLength(1);
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: adminHeaders() })).status).toBe(200);
  });

  it('returns 404 for unknown boss', async () => {
    const res = await testRequest('POST', 'http://localhost/api/bosses/nonexistent/token', adminHeaders());
    expect(res.status).toBe(404);
  });

  it('rejects non-admin bosses', async () => {
    const res = await testRequest('POST', `http://localhost/api/bosses/${createdBossId}/token`,
      viewerHeaders());
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'admin required' });
  });
});

describe('DELETE /api/bosses/:id', () => {
  it('deletes a boss', async () => {
    const res = await testRequest('DELETE', `http://localhost/api/bosses/${createdBossId}`, adminHeaders());
    expect(res.status).toBe(200);
  });

  it('returns 404 for already deleted boss', async () => {
    const res = await testRequest('DELETE', `http://localhost/api/bosses/${createdBossId}`, adminHeaders());
    expect(res.status).toBe(404);
  });
});
