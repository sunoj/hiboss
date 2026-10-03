// End-to-end device enrolment: grouped profiles, atomic approval, device proof,
// first-boss bootstrap and pairing roles, all through the worker's HTTP surface.
// Depends on cloudflare:test SELF/env and the shared D1 seed.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';

const BASE = 'https://test.local';
const ADMIN = 'devices-admin-token';
type Json = Record<string, unknown>;
type Delivered = { profile: string; name: string; agent_id: string; key: string };

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('devices-admin', 'admin', ADMIN, 'devices-admin');
});

async function join(body: unknown, headers: Record<string, string> = {}): Promise<Response> {
  return SELF.fetch(`${BASE}/api/join`, { method: 'POST', body: JSON.stringify(body),
    headers: { 'Content-Type': 'application/json', ...headers } });
}

function request(label: string, names: Record<string, string>): Json {
  return { device: { label, host: `${label}.local` }, profiles: Object.entries(names).map(([profile, name]) => ({ profile, name })) };
}

async function approve(requestId: string): Promise<Response> {
  return SELF.fetch(`${BASE}/api/boss/join-requests/${requestId}/approve`, { method: 'POST', headers: { Authorization: `Bearer ${ADMIN}` } });
}

async function poll(token: string): Promise<Json> {
  return (await SELF.fetch(`${BASE}/api/join/status?token=${token}`)).json() as Promise<Json>;
}

async function enrol(label: string, names: Record<string, string>, headers: Record<string, string> = {}): Promise<{ device_id: string; profiles: Delivered[] }> {
  const created = await join(request(label, names), headers);
  expect(created.status).toBe(201);
  const { request_id, poll_token } = await created.json() as { request_id: string; poll_token: string };
  expect((await approve(request_id)).status).toBe(200);
  return poll(poll_token) as unknown as Promise<{ device_id: string; profiles: Delivered[] }>;
}

describe('device enrolment', () => {
  it('approves every profile of a device at once and delivers working keys once', async () => {
    const created = await join(request('dev-a', { claude: 'dev-a-claude', codex: 'dev-a-codex' }));
    const { request_id, poll_token } = await created.json() as { request_id: string; poll_token: string };
    expect(await poll(poll_token)).toMatchObject({ status: 'pending', device_label: 'dev-a' });
    const approved = await approve(request_id);
    const body = await approved.json() as Json;
    expect(body).toMatchObject({ status: 'approved', device_id: expect.stringMatching(/^d_/) });
    expect(JSON.stringify(body)).not.toContain('hb_');
    const delivered = await poll(poll_token) as { device_id: string; profiles: Delivered[] };
    expect(delivered.profiles.map(p => p.profile)).toEqual(['claude', 'codex']);
    for (const profile of delivered.profiles) {
      const me = await SELF.fetch(`${BASE}/api/agents/me`, { headers: { Authorization: `Bearer ${profile.key}` } });
      expect(await me.json()).toMatchObject({ id: profile.agent_id, name: profile.name });
    }
    const devices = await env.DB.prepare('SELECT DISTINCT device_id FROM api_keys WHERE name LIKE ?').bind('dev-a-%').all();
    expect(devices.results).toEqual([{ device_id: delivered.device_id }]);
    expect(await poll(poll_token)).toMatchObject({ status: 'approved', delivered: true });
    expect(JSON.stringify(await poll(poll_token))).not.toContain('hb_');
  });

  it('creates nothing when one name is taken by approval time', async () => {
    const created = await join(request('dev-b', { claude: 'dev-b-claude', codex: 'dev-b-codex' }));
    const { request_id } = await created.json() as { request_id: string };
    await env.DB.prepare('INSERT INTO api_keys (id, name) VALUES (?, ?)').bind('dev-b-squatter', 'dev-b-codex').run();
    const response = await approve(request_id);
    expect(response.status).toBe(409);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM api_keys WHERE name = ?').bind('dev-b-claude').first('n')).toBe(0);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM devices WHERE label = ?').bind('dev-b').first('n')).toBe(0);
    expect(await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?').bind(request_id).first('status')).toBe('pending');
  });

  it('adds a profile to an existing device only with a valid device proof', async () => {
    const first = await enrol('dev-c', { claude: 'dev-c-claude' });
    const added = await enrol('ignored-label', { aid: 'dev-c-aid' }, { 'X-Device-Proof': first.profiles[0].key });
    expect(added.device_id).toBe(first.device_id);
    expect(await env.DB.prepare('SELECT device_label FROM join_requests WHERE device_id = ? ORDER BY created_at DESC')
      .bind(first.device_id).first('device_label')).toBe('dev-c');
    const forged = await join(request('dev-c', { gemini: 'dev-c-gemini' }), { 'X-Device-Proof': 'hb_not_a_key' });
    expect(forged.status).toBe(401);
  });

  it('rejects the legacy single-name payload and malformed profiles', async () => {
    const legacy = await join({ name: 'legacy-agent' });
    expect(legacy.status).toBe(400);
    expect(((await legacy.json()) as Json).error).toContain('hiboss setup');
    const duplicate = await join({ device: { label: 'dev-d' }, profiles: [{ profile: 'claude', name: 'x1' }, { profile: 'claude', name: 'x2' }] });
    expect(duplicate.status).toBe(400);
    const tooMany = await join(request('dev-d', Object.fromEntries(Array.from({ length: 9 }, (_, i) => [`p${i}`, `dev-d-${i}`]))));
    expect(tooMany.status).toBe(400);
    const badName = await join(request('dev-d', { claude: '<script>' }));
    expect(badName.status).toBe(400);
  });
});

describe('first-boss bootstrap and pairing roles', () => {
  async function bootstrap(secret?: string): Promise<Response> {
    return SELF.fetch(`${BASE}/api/bootstrap/boss`, { method: 'POST', body: JSON.stringify({ name: 'First Boss' }),
      headers: { 'Content-Type': 'application/json', ...(secret ? { 'X-Bootstrap-Secret': secret } : {}) } });
  }

  it('requires a configured secret, creates one admin boss and returns only a pairing code', async () => {
    const previous = env.BOOTSTRAP_SECRET;
    await env.DB.prepare('DELETE FROM bosses').run();
    try {
      env.BOOTSTRAP_SECRET = '';
      expect((await bootstrap('anything')).status).toBe(403);
      env.BOOTSTRAP_SECRET = 'devices-bootstrap-secret';
      expect((await bootstrap('wrong')).status).toBe(401);
      const created = await bootstrap('devices-bootstrap-secret');
      expect(created.status).toBe(201);
      const body = await created.json() as { boss: Json; code: string };
      expect(body.boss).toMatchObject({ role: 'admin', name: 'First Boss' });
      expect(body.code).toMatch(/^hb_pair_[0-9a-f]{64}$/);
      expect(JSON.stringify(body)).not.toContain('hb_boss_');
      const redeemed = await SELF.fetch(`${BASE}/api/pairing/redeem`, { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code: body.code, device_label: 'First Mac' }) });
      expect(await redeemed.json()).toMatchObject({ token: expect.stringMatching(/^hb_boss_/), boss: { role: 'admin' } });
      expect((await bootstrap('devices-bootstrap-secret')).status).toBe(409);
    } finally {
      env.BOOTSTRAP_SECRET = previous;
    }
  });

  it('lets a manager issue pairing codes and refuses a viewer', async () => {
    await seedBossToken('devices-manager', 'manager', 'devices-manager-token');
    await seedBossToken('devices-viewer', 'viewer', 'devices-viewer-token');
    const issue = (token: string) => SELF.fetch(`${BASE}/api/boss/pairing`, { method: 'POST', headers: { Authorization: `Bearer ${token}` } });
    expect((await issue('devices-manager-token')).status).toBe(200);
    expect((await issue('devices-viewer-token')).status).toBe(403);
  });
});
