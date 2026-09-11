// Worker API tests for client minting, legacy compatibility, and cascade revocation.
// Covers real D1 persistence and bearer authentication; depends on cloudflare:test.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import type { BossClient } from './types';

const ROOT = 'clients-root-token';
const VIEWER = 'clients-viewer-token';
const headers = (token = ROOT): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
const url = 'https://test.local/api/boss/clients';
type Grant = { client: BossClient; token: string };

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Clients Boss', 'admin', ROOT, 'clients-boss');
  await seedBossToken('Clients Viewer', 'viewer', VIEWER, 'clients-viewer');
});

async function mint(token = ROOT, kind = 'web'): Promise<Grant> {
  const response = await SELF.fetch(url, { method: 'POST', headers: headers(token), body: JSON.stringify({ kind, label: 'Test browser' }) });
  expect(response.status).toBe(201);
  return response.json() as Promise<Grant>;
}

it('exchanges a legacy bearer for an independent client token without invalidating it', async () => {
  const grant = await mint();
  expect(grant.client).toMatchObject({ kind: 'web', label: 'Test browser', is_current: false });
  const list = await SELF.fetch(url, { headers: headers(grant.token) });
  expect(list.status).toBe(200);
  const data = await list.json() as { clients: BossClient[] };
  expect(data.clients.find(client => client.id === grant.client.id)?.is_current).toBe(true);
  const token = await env.DB.prepare('SELECT client_id FROM boss_tokens WHERE token_hash = ?')
    .bind(await hashApiKey(grant.token)).first<{ client_id: string }>();
  expect(token?.client_id).toBe(grant.client.id);
  expect((await SELF.fetch(url, { headers: headers() })).status).toBe(200);
  expect(JSON.stringify(data)).not.toContain(grant.token);
  expect(JSON.stringify(data)).not.toContain('token_hash');
});

it('allows viewers to mint only for themselves and hides other bosses clients', async () => {
  const grant = await mint(VIEWER);
  const row = await env.DB.prepare('SELECT boss_id FROM boss_clients WHERE id = ?').bind(grant.client.id).first<{ boss_id: string }>();
  expect(row?.boss_id).toBe('clients-viewer');
  expect((await SELF.fetch(`${url}/${grant.client.id}`, { method: 'DELETE', headers: headers() })).status).toBe(404);
  const list = await SELF.fetch(url, { headers: headers() });
  expect(JSON.stringify(await list.json())).not.toContain(grant.client.id);
});

it('blocks self-revocation but preserves the existing token self-revoke path', async () => {
  const grant = await mint(VIEWER);
  expect((await SELF.fetch(`${url}/${grant.client.id}`, { method: 'DELETE', headers: headers(grant.token) })).status).toBe(403);
  const row = await env.DB.prepare('SELECT id FROM boss_tokens WHERE client_id = ?').bind(grant.client.id).first<{ id: string }>();
  expect((await SELF.fetch(`https://test.local/api/boss/tokens/${row?.id}`, { method: 'DELETE', headers: headers(grant.token) })).status).toBe(200);
  expect((await SELF.fetch(url, { headers: headers(grant.token) })).status).toBe(401);
});

it('stamps push ownership and revokes all tokens, signing keys, and devices atomically', async () => {
  const grant = await mint(ROOT, 'ios');
  const token = await env.DB.prepare('SELECT id FROM boss_tokens WHERE client_id = ?').bind(grant.client.id).first<{ id: string }>();
  await env.DB.prepare("INSERT INTO boss_signing_keys (id, boss_id, boss_token_id, algorithm, client_kind, public_key, client_id) VALUES ('client-key', 'clients-boss', ?, 'ES256', 'ios', 'test-key', ?)")
    .bind(token?.id, grant.client.id).run();
  await env.DB.prepare("INSERT INTO boss_tokens (id, boss_id, label, token_hash, client_id) VALUES ('client-second-token', 'clients-boss', 'second', ?, ?)")
    .bind(await hashApiKey('client-second-bearer'), grant.client.id).run();
  const push = await SELF.fetch('https://test.local/api/boss/devices', { method: 'POST', headers: headers(grant.token),
    body: JSON.stringify({ token: 'aabbccdd', bundleId: 'ai.hiboss.app', environment: 'sandbox', platform: 'ios' }) });
  expect(push.status).toBe(200);
  const device = await env.DB.prepare("SELECT client_id FROM boss_devices WHERE device_token = 'aabbccdd'").first<{ client_id: string }>();
  expect(device?.client_id).toBe(grant.client.id);
  const list = await (await SELF.fetch(url, { headers: headers() })).json() as { clients: BossClient[] };
  expect(list.clients.find(client => client.id === grant.client.id)).toMatchObject({ has_push_device: true, has_signing_key: true });
  expect((await SELF.fetch(`${url}/${grant.client.id}`, { method: 'DELETE', headers: headers() })).status).toBe(200);
  for (const bearer of [grant.token, 'client-second-bearer']) {
    expect((await SELF.fetch(url, { headers: headers(bearer) })).status).toBe(401);
  }
  expect(await env.DB.prepare('SELECT id FROM boss_devices WHERE client_id = ?').bind(grant.client.id).first()).toBeNull();
  expect(await env.DB.prepare("SELECT revoked_at FROM boss_signing_keys WHERE id = 'client-key'").first()).toMatchObject({ revoked_at: expect.any(String) });
  const revokedList = await (await SELF.fetch(url, { headers: headers() })).json() as { clients: BossClient[] };
  expect(revokedList.clients.find(client => client.id === grant.client.id)).toMatchObject({
    revoked_at: expect.any(String), has_push_device: false, has_signing_key: true,
  });
  expect(await env.DB.prepare("SELECT action FROM audit_log WHERE resource_id = ?").bind(grant.client.id).first()).toEqual({ action: 'client.revoke' });
});

it('updates client activity once per minute, including dual-auth requests', async () => {
  const grant = await mint();
  await SELF.fetch(url, { headers: headers(grant.token) });
  const first = await env.DB.prepare('SELECT last_seen_at FROM boss_clients WHERE id = ?').bind(grant.client.id).first<{ last_seen_at: string }>();
  expect(first?.last_seen_at).toBeTruthy();
  // A deliberately recognizable timestamp inside the throttle window must survive.
  await env.DB.prepare("UPDATE boss_clients SET last_seen_at = datetime('now', '-20 seconds') WHERE id = ?").bind(grant.client.id).run();
  const before = await env.DB.prepare('SELECT last_seen_at FROM boss_clients WHERE id = ?').bind(grant.client.id).first();
  await SELF.fetch(url, { headers: headers(grant.token) });
  expect(await env.DB.prepare('SELECT last_seen_at FROM boss_clients WHERE id = ?').bind(grant.client.id).first()).toEqual(before);
  await env.DB.prepare("UPDATE boss_clients SET last_seen_at = datetime('now', '-2 minutes') WHERE id = ?").bind(grant.client.id).run();
  await SELF.fetch('https://test.local/api/panels', { headers: headers(grant.token) });
  expect(await env.DB.prepare('SELECT last_seen_at FROM boss_clients WHERE id = ?').bind(grant.client.id).first()).not.toEqual(before);
});

it.each([{}, { kind: 'android', label: 'Phone' }, { kind: 'web', label: '' }, { kind: 'web', label: 'x'.repeat(101) }])('rejects invalid registrations: %j', async body => {
  expect((await SELF.fetch(url, { method: 'POST', headers: headers(), body: JSON.stringify(body) })).status).toBe(400);
});

it('rejects anonymous minting', async () => {
  expect((await SELF.fetch(url, { method: 'POST', body: JSON.stringify({ kind: 'web', label: 'Browser' }) })).status).toBe(401);
});

it('re-parents a device token to the registering boss, stamping its client and auditing the move', async () => {
  const owner = await mint(ROOT, 'ios');
  const other = await mint(VIEWER, 'ios');
  const register = (token: string) => SELF.fetch('https://test.local/api/boss/devices', {
    method: 'POST', headers: headers(token), body: JSON.stringify({
      token: '11223344', bundleId: 'ai.hiboss.app', environment: 'sandbox', platform: 'ios',
    }),
  });
  expect((await register(owner.token)).status).toBe(200);
  const moved = await register(other.token);
  expect(moved.status).toBe(200);
  expect(await moved.json()).toEqual({ ok: true, reparented: true });
  expect(await env.DB.prepare("SELECT boss_id, client_id FROM boss_devices WHERE device_token = '11223344'").first())
    .toEqual({ boss_id: 'clients-viewer', client_id: other.client.id });
});
