// Round-two regressions: a revoked boss token stops every push to devices registered under it.
// Covers self-revoke, revoke-others, admin delete, rotation, client-less tokens and destinations.
// Depends on the Worker API, seeded D1, the legacy push fan-out and destination resolution.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { notifyBossAgents } from '../notify';
import { resolveDestinations } from '../delivery/destinations';
import { apnsEnv, captureFetch } from '../push/resolution-test-support';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import type { MessageRow } from '../types';

const api = 'https://test.local/api';
const unique = (name: string): string => `u2-${name}-${crypto.randomUUID().slice(0, 8)}`;
const headers = (token: string): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
const hex = (): string => crypto.randomUUID().replaceAll('-', '') + crypto.randomUUID().replaceAll('-', '');

beforeAll(async () => { await seedDatabase(); });
afterEach(() => { vi.unstubAllGlobals(); });

interface Fixture { bossId: string; keeper: string; client: { id: string; token: string; tokenId: string } }

async function fixture(name: string): Promise<Fixture> {
  const bossId = unique(name);
  const keeper = `hb_${bossId}`;
  await seedBossToken(bossId, 'admin', keeper, bossId);
  const response = await SELF.fetch(`${api}/boss/clients`, {
    method: 'POST', headers: headers(keeper), body: JSON.stringify({ kind: 'ios', label: unique('phone') }),
  });
  expect(response.status).toBe(201);
  const body = await response.json<{ client: { id: string }; token: string }>();
  return { bossId, keeper, client: { id: body.client.id, token: body.token, tokenId: await tokenId(body.token) } };
}

async function tokenId(token: string): Promise<string> {
  const row = await env.DB.prepare('SELECT id FROM boss_tokens WHERE token_hash = ?').bind(await hashApiKey(token)).first<{ id: string }>();
  if (!row) throw new Error('token fixture missing');
  return row.id;
}

async function register(token: string): Promise<string> {
  const device = hex();
  const response = await SELF.fetch(`${api}/boss/devices`, {
    method: 'POST', headers: headers(token),
    body: JSON.stringify({ token: device, bundleId: 'ai.hiboss.app', environment: 'sandbox', platform: 'ios' }),
  });
  expect(response.status).toBe(200);
  return device;
}

async function pushedTo(): Promise<string[]> {
  const captured = captureFetch();
  const message = { id: unique('msg'), agent_id: getTestAgentId(), direction: 'agent_to_boss', mode: 'async', channel: 'api',
    body: 'Secret build status', status: 'sent', priority: 'high', metadata: null } as unknown as MessageRow;
  await notifyBossAgents(await apnsEnv(), getTestAgentId(), message);
  return captured.map(request => request.url);
}

const sent = (urls: string[], device: string): boolean => urls.some(url => url.endsWith(`/3/device/${device}`));

type Revoke = (fixture: Fixture) => Promise<Response>;
const revocations: Array<[string, Revoke]> = [
  ['token self-revoke', f => SELF.fetch(`${api}/boss/tokens/${f.client.tokenId}`, { method: 'DELETE', headers: headers(f.client.token) })],
  ['admin token delete', f => SELF.fetch(`${api}/boss/tokens/${f.client.tokenId}`, { method: 'DELETE', headers: headers(f.keeper) })],
  ['revoke-others', f => SELF.fetch(`${api}/boss/tokens/revoke-others`, { method: 'POST', headers: headers(f.keeper) })],
];

it.each(revocations)('EN-2 %s stops pushes to the revoked token\'s device and keeps the live one', async (_name, revoke) => {
  const f = await fixture('revoke');
  const revoked = await register(f.client.token);
  const live = await register(f.keeper);
  const before = await pushedTo();
  expect(sent(before, revoked) && sent(before, live)).toBe(true);
  expect((await revoke(f)).status).toBe(200);
  const after = await pushedTo();
  expect(sent(after, live)).toBe(true);
  expect(sent(after, revoked)).toBe(false);
  expect(await env.DB.prepare('SELECT 1 FROM boss_devices WHERE device_token = ?').bind(revoked).first()).toBeNull();
  expect(await env.DB.prepare('SELECT revoked_at FROM boss_clients WHERE id = ?').bind(f.client.id).first<{ revoked_at: string | null }>())
    .toEqual({ revoked_at: expect.any(String) });
});

it('EN-2 admin rotation stops pushes to every device registered before it', async () => {
  const f = await fixture('rotate');
  const rotator = unique('rotator');
  await seedBossToken(rotator, 'admin', `hb_${rotator}`, rotator);
  const clientDevice = await register(f.client.token);
  const keeperDevice = await register(f.keeper);
  const rotated = await SELF.fetch(`${api}/bosses/${f.bossId}/token`, { method: 'POST', headers: headers(`hb_${rotator}`) });
  expect(rotated.status).toBe(200);
  const fresh = await register((await rotated.json<{ token: string }>()).token);
  const after = await pushedTo();
  expect(sent(after, fresh)).toBe(true);
  expect(sent(after, clientDevice) || sent(after, keeperDevice)).toBe(false);
});

it('EN-2 a device registered under a client-less token stops with that token', async () => {
  const f = await fixture('clientless');
  const second = `hb_${unique('second')}`;
  await env.DB.prepare("INSERT INTO boss_tokens (boss_id, label, token_hash) VALUES (?, 'second', ?)")
    .bind(f.bossId, await hashApiKey(second)).run();
  const device = await register(second);
  expect(sent(await pushedTo(), device)).toBe(true);
  expect((await SELF.fetch(`${api}/boss/tokens/${await tokenId(second)}`, { method: 'DELETE', headers: headers(f.keeper) })).status).toBe(200);
  expect(sent(await pushedTo(), device)).toBe(false);
});

it('EN-2 destination resolution drops the APNs destination of a revoked token\'s device', async () => {
  const f = await fixture('destination');
  const device = await register(f.client.token);
  const row = await env.DB.prepare('SELECT id FROM boss_devices WHERE device_token = ?').bind(device).first<{ id: string }>();
  const destination = unique('apns');
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, client_id, target, label)
    VALUES (?, ?, 'apns', ?, ?, 'iOS push')`).bind(destination, f.bossId, f.client.id, JSON.stringify({ device_id: row?.id })).run();
  const message = { agent_id: getTestAgentId(), priority: 'high', session_id: null, direction: 'agent_to_boss' } as const;
  expect((await resolveDestinations(env, message)).map(d => d.id)).toContain(destination);
  expect((await SELF.fetch(`${api}/boss/tokens/${f.client.tokenId}`, { method: 'DELETE', headers: headers(f.client.token) })).status).toBe(200);
  expect((await resolveDestinations(env, message)).map(d => d.id)).not.toContain(destination);
});
