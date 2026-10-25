// Round-two regressions: a pairing code dies with the token (and client) that issued it.
// Covers admin rotation, client revocation and issuer self-revoke before redemption.
// Depends on the Worker API and seeded D1.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { seedBossToken, seedDatabase } from '../test-helpers';

const api = 'https://test.local/api';
const unique = (name: string): string => `p2-${name}-${crypto.randomUUID().slice(0, 8)}`;
const headers = (token: string): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });

beforeAll(async () => { await seedDatabase(); });

async function admin(name: string): Promise<{ id: string; token: string }> {
  const id = unique(name);
  const token = `hb_${id}`;
  await seedBossToken(id, 'admin', token, id);
  return { id, token };
}

async function issue(token: string): Promise<string> {
  const response = await SELF.fetch(`${api}/boss/pairing`, { method: 'POST', headers: headers(token) });
  expect(response.status).toBe(200);
  return (await response.json<{ code: string }>()).code;
}

function redeem(code: string): Promise<Response> {
  return SELF.fetch(`${api}/pairing/redeem`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code, device_label: 'Redeemer' }),
  });
}

async function mintClient(token: string): Promise<{ id: string; token: string }> {
  const response = await SELF.fetch(`${api}/boss/clients`, {
    method: 'POST', headers: headers(token), body: JSON.stringify({ kind: 'ios', label: unique('phone') }),
  });
  expect(response.status).toBe(201);
  const body = await response.json<{ client: { id: string }; token: string }>();
  return { id: body.client.id, token: body.token };
}

async function tokenId(token: string): Promise<string> {
  const row = await env.DB.prepare('SELECT id FROM boss_tokens WHERE token_hash = ?').bind(await hashApiKey(token)).first<{ id: string }>();
  if (!row) throw new Error('token fixture missing');
  return row.id;
}

async function expectLiveTokens(bossId: string, count: number): Promise<void> {
  const live = await env.DB.prepare('SELECT COUNT(*) AS n FROM boss_tokens WHERE boss_id = ? AND revoked_at IS NULL')
    .bind(bossId).first<{ n: number }>();
  expect(live?.n).toBe(count);
}

it('EN-1 control: a code from a live issuer redeems once', async () => {
  const boss = await admin('control');
  const code = await issue(boss.token);
  const response = await redeem(code);
  expect(response.status).toBe(200);
  const { token } = await response.json<{ token: string }>();
  expect((await SELF.fetch(`${api}/boss/me`, { headers: headers(token) })).status).toBe(200);
  expect((await redeem(code)).status).toBe(400);
});

it('EN-1 a code issued before an admin rotation cannot be redeemed after it', async () => {
  const target = await admin('rotated');
  const rotator = await admin('rotator');
  const code = await issue(target.token);
  expect((await SELF.fetch(`${api}/bosses/${target.id}/token`, { method: 'POST', headers: headers(rotator.token) })).status).toBe(200);
  expect((await redeem(code)).status).toBe(400);
  await expectLiveTokens(target.id, 1);
});

it('EN-1 a code issued by a client cannot be redeemed after that client is revoked', async () => {
  const boss = await admin('client-owner');
  const client = await mintClient(boss.token);
  const code = await issue(client.token);
  expect((await SELF.fetch(`${api}/boss/clients/${client.id}`, { method: 'DELETE', headers: headers(boss.token) })).status).toBe(200);
  expect((await redeem(code)).status).toBe(400);
});

it('EN-1 a code cannot be redeemed after its issuing token revokes itself', async () => {
  const boss = await admin('self-revoke');
  const sibling = await mintClient(boss.token);
  const code = await issue(sibling.token);
  const id = await tokenId(sibling.token);
  expect((await SELF.fetch(`${api}/boss/tokens/${id}`, { method: 'DELETE', headers: headers(sibling.token) })).status).toBe(200);
  expect((await redeem(code)).status).toBe(400);
  await expectLiveTokens(boss.id, 1);
});

it('EN-1 a code without an issuing token is refused once the boss holds a token', async () => {
  const boss = await admin('issuerless');
  const code = `hb_pair_${'c'.repeat(64)}`;
  await env.DB.prepare("INSERT INTO boss_pairing_codes (boss_id, code_hash, expires_at) VALUES (?, ?, '2999-01-01T00:00:00Z')")
    .bind(boss.id, await hashApiKey(code)).run();
  expect((await redeem(code)).status).toBe(400);
});
