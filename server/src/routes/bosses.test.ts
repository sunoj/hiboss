// Tests for /api/bosses CRUD, access management, preferences, and token generation.
// Covers create, get, update, delete, grant/revoke access, token issuance.
// Depends on cloudflare:test, test-helpers, and the Hono app.
import { testRequest, returnsStatus, testJson } from '../test-request';
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
  it('rejects agent tokens', returnsStatus(401, () =>
    testRequest('POST', 'http://localhost/api/bosses', authHeaders(),
      { name: 'Agent Rejected' })));

  it('creates a boss with defaults', async () => {
    const data = await testJson(201, testRequest('POST', 'http://localhost/api/bosses', adminHeaders(),
      { name: 'Test Boss' })) as any;
    expect(data.id).toBeTruthy();
    expect(data.name).toBe('Test Boss');
    expect(data.role).toBe('admin');
    createdBossId = data.id;
  });

  it('creates a boss with explicit role and telegram ID', async () => {
    const data = await testJson(201, testRequest('POST', 'http://localhost/api/bosses', adminHeaders(),
      { name: 'Viewer Boss', role: 'viewer', telegram_user_id: '12345' })) as any;
    expect(data.role).toBe('viewer');
    expect(data.telegram_user_id).toBe('12345');
  });

  it('rejects empty name', returnsStatus(400, () =>
    testRequest('POST', 'http://localhost/api/bosses', adminHeaders(), { name: '' })));

  it('rejects non-admin bosses', returnsStatus(403, () =>
    testRequest('POST', 'http://localhost/api/bosses', viewerHeaders(),
      { name: 'Forbidden Boss' })));

  it('defaults invalid role to admin', async () => {
    const data = await testJson(201, testRequest('POST', 'http://localhost/api/bosses', adminHeaders(),
      { name: 'Invalid Role', role: 'superadmin' })) as any;
    expect(data.role).toBe('admin');
  });
});

describe('GET /api/bosses', () => {
  it('lists all bosses for authenticated bosses', async () => {
    const data = await testJson(200,
      SELF.fetch('http://localhost/api/bosses', { headers: viewerHeaders() })) as any;
    expect(data.bosses).toBeInstanceOf(Array);
    expect(data.bosses.length).toBeGreaterThanOrEqual(2);
  });
});

describe('GET /api/bosses/:id', () => {
  it('returns boss by full ID', async () => {
    const data = await testJson(200,
      SELF.fetch(`http://localhost/api/bosses/${createdBossId}`, { headers: viewerHeaders() })) as any;
    expect(data.id).toBe(createdBossId);
    expect(data.agents).toBeInstanceOf(Array);
  });

  it('supports short ID prefix', async () => {
    const prefix = createdBossId.slice(0, 8);
    const data = await testJson(200,
      SELF.fetch(`http://localhost/api/bosses/${prefix}`, { headers: viewerHeaders() })) as any;
    expect(data.id).toBe(createdBossId);
  });

  it('returns 404 for unknown boss', returnsStatus(404, () =>
    SELF.fetch('http://localhost/api/bosses/nonexistent', { headers: viewerHeaders() })));
});

describe('PATCH /api/bosses/:id', () => {
  it('updates boss name', async () => {
    const data = await testJson(200,
      testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
        { name: 'Updated Boss' })) as any;
    expect(data.name).toBe('Updated Boss');
  });

  it('updates role', async () => {
    const data = await testJson(200,
      testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
        { role: 'manager' })) as any;
    expect(data.role).toBe('manager');
  });

  it('rejects invalid role', returnsStatus(400, () =>
    testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { role: 'superadmin' })));

  it('rejects empty name', returnsStatus(400, () =>
    testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { name: '  ' })));

  it('rejects no valid fields', returnsStatus(400, () =>
    testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, adminHeaders(),
      { unknown_field: 'value' })));

  it('rejects non-admin bosses', returnsStatus(403, () =>
    testRequest('PATCH', `http://localhost/api/bosses/${createdBossId}`, viewerHeaders(),
      { name: 'Forbidden Update' })));
});

describe('Boss access management', () => {
  it('grants agent access', returnsStatus(201, () =>
    testRequest('POST', `http://localhost/api/bosses/${createdBossId}/access`,
      adminHeaders(), { agent_id: 'test-agent-id' })));

  it('rejects grant without agent_id', returnsStatus(400, () =>
    testRequest('POST', `http://localhost/api/bosses/${createdBossId}/access`,
      adminHeaders(), {})));

  it('revokes agent access', returnsStatus(200, () => testRequest('DELETE',
      `http://localhost/api/bosses/${createdBossId}/access/test-agent-id`, adminHeaders())));

  it('returns 404 revoking non-existent access', returnsStatus(404, () => testRequest('DELETE',
      `http://localhost/api/bosses/${createdBossId}/access/nonexistent`, adminHeaders())));

  it('rejects non-admin access changes', returnsStatus(403, () =>
    testRequest('POST', `http://localhost/api/bosses/${createdBossId}/access`,
      viewerHeaders(), { agent_id: 'test-agent-id' })));
});

describe('POST /api/bosses/:id/token', () => {
  it('generates a boss auth token', async () => {
    const data = await testJson(200, testRequest('POST', `http://localhost/api/bosses/${createdBossId}/token`,
      adminHeaders())) as any;
    expect(data.token).toMatch(/^hb_boss_/);
    expect(data.id).toBe(createdBossId);
    generatedToken = data.token;
  });

  it('revokes the prior target token when rotating', async () => {
    const data = await testJson(200, testRequest('POST', `http://localhost/api/bosses/${createdBossId}/token`,
      adminHeaders())) as { token: string };
    expect((await testRequest('GET', 'http://localhost/api/boss/me',
      { Authorization: `Bearer ${generatedToken}` })).status).toBe(401);
    expect((await testRequest('GET', 'http://localhost/api/boss/me',
      { Authorization: `Bearer ${data.token}` })).status).toBe(200);
    const live = await env.DB.prepare('SELECT token_hash FROM boss_tokens WHERE boss_id = ? AND revoked_at IS NULL')
      .bind(createdBossId).all<{ token_hash: string }>();
    expect(live.results).toHaveLength(1);
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: adminHeaders() })).status).toBe(200);
  });

  it('returns 404 for unknown boss', returnsStatus(404, () =>
    testRequest('POST', 'http://localhost/api/bosses/nonexistent/token', adminHeaders())));

  it('rejects non-admin bosses', async () => {
    const res = await testRequest('POST', `http://localhost/api/bosses/${createdBossId}/token`,
      viewerHeaders());
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'admin required' });
  });
});

describe('DELETE /api/bosses/:id', () => {
  it('deletes a boss', returnsStatus(200, () =>
    testRequest('DELETE', `http://localhost/api/bosses/${createdBossId}`, adminHeaders())));

  it('returns 404 for already deleted boss', returnsStatus(404, () =>
    testRequest('DELETE', `http://localhost/api/bosses/${createdBossId}`, adminHeaders())));
});
