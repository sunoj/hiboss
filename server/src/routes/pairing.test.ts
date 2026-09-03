// Integration tests for boss QR pairing and independent token authentication.
// Covers issuance, redemption, expiry, single-use concurrency, and revocation.
// Depends on cloudflare:test, shared seed helpers, and the worker app.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { seedBossToken, seedDatabase } from '../test-helpers';

const BOSS_TOKEN = 'hb_boss_pairing_test_existing_token';
const RATE_LIMIT_TOKEN = 'hb_boss_pairing_rate_limit_token';
const TOKEN_MANAGEMENT_TOKEN = 'hb_boss_pairing_token_management_token';
let bossId: string;

beforeAll(async () => {
  await seedDatabase();
  bossId = await seedBossToken('Pairing Boss', 'admin', BOSS_TOKEN, 'pairing-boss');
  await seedBossToken('Rate Limit Boss', 'viewer', RATE_LIMIT_TOKEN, 'pairing-rate-limit-boss');
  await seedBossToken('Token Management Boss', 'admin', TOKEN_MANAGEMENT_TOKEN, 'pairing-token-management-boss');
});

function bossHeaders(token: string = BOSS_TOKEN): Record<string, string> {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

async function issueCode(token: string = BOSS_TOKEN): Promise<{ code: string; expires_at: string }> {
  const response = await SELF.fetch('http://localhost/api/boss/pairing', {
    method: 'POST',
    headers: bossHeaders(token),
  });
  expect(response.status).toBe(200);
  return await response.json() as { code: string; expires_at: string };
}

describe('POST /api/boss/pairing', () => {
  it('issues a long random code and stores only its hash', async () => {
    const data = await issueCode();
    expect(data.code).toMatch(/^hb_pair_[0-9a-f]{64}$/);
    expect(new Date(data.expires_at).getTime()).toBeGreaterThan(Date.now());
    const row = await env.DB.prepare('SELECT boss_id, code_hash FROM boss_pairing_codes WHERE boss_id = ? ORDER BY created_at DESC LIMIT 1')
      .bind(bossId).first<{ boss_id: string; code_hash: string }>();
    expect(row?.boss_id).toBe(bossId);
    expect(row?.code_hash).toBe(await hashApiKey(data.code));
    expect(row?.code_hash).not.toBe(data.code);
  });

  it('rejects agent authentication', async () => {
    const response = await SELF.fetch('http://localhost/api/boss/pairing', {
      method: 'POST',
      headers: { Authorization: 'Bearer hb_test_key_0000000000000000' },
    });
    expect(response.status).toBe(401);
  });

  it('limits active pairing codes per boss', async () => {
    const codes: string[] = [];
    for (let index = 0; index < 5; index += 1) codes.push((await issueCode(RATE_LIMIT_TOKEN)).code);
    for (const code of codes) {
      const redeemed = await SELF.fetch('http://localhost/api/pairing/redeem', {
        method: 'POST', body: JSON.stringify({ code, device_label: 'Rate-limited device' }),
      });
      expect(redeemed.status).toBe(200);
    }
    const response = await SELF.fetch('http://localhost/api/boss/pairing', {
      method: 'POST', headers: bossHeaders(RATE_LIMIT_TOKEN),
    });
    expect(response.status).toBe(429);
  });
});

describe('POST /api/pairing/redeem', () => {
  it('returns a new labeled token while the existing token remains valid', async () => {
    const { code } = await issueCode();
    const response = await SELF.fetch('http://localhost/api/pairing/redeem', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, device_label: 'Alice iPhone' }),
    });
    expect(response.status).toBe(200);
    const data = await response.json() as { token: string; boss: { id: string; name: string; role: string } };
    expect(data.token).toMatch(/^hb_boss_[0-9a-f]{64}$/);
    expect(data.boss).toEqual({ id: bossId, name: 'Pairing Boss', role: 'admin' });
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders(data.token) })).status).toBe(200);
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders() })).status).toBe(200);
    const token = await env.DB.prepare('SELECT label, revoked_at FROM boss_tokens WHERE token_hash = ?')
      .bind(await hashApiKey(data.token)).first<{ label: string; revoked_at: string | null }>();
    expect(token).toEqual({ label: 'Alice iPhone', revoked_at: null });
  });

  it('consumes a code only once', async () => {
    const { code } = await issueCode();
    const request = () => SELF.fetch('http://localhost/api/pairing/redeem', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code, device_label: 'One-use device' }),
    });
    const responses = await Promise.all([request(), request()]);
    expect(responses.map((response) => response.status).sort()).toEqual([200, 400]);
  });

  it('rejects expired and malformed codes', async () => {
    const { code } = await issueCode();
    await env.DB.prepare('UPDATE boss_pairing_codes SET expires_at = ? WHERE code_hash = ?')
      .bind('2000-01-01T00:00:00.000Z', await hashApiKey(code)).run();
    const expired = await SELF.fetch('http://localhost/api/pairing/redeem', {
      method: 'POST', body: JSON.stringify({ code, device_label: 'Expired device' }),
    });
    expect(expired.status).toBe(400);
    const malformed = await SELF.fetch('http://localhost/api/pairing/redeem', {
      method: 'POST', body: JSON.stringify({ code: 'not-a-code', device_label: '' }),
    });
    expect(malformed.status).toBe(400);
    const unsafe = await SELF.fetch('http://localhost/api/pairing/redeem', {
      method: 'POST', body: JSON.stringify({ code, device_label: '<script>alert(1)</script>' }),
    });
    expect(unsafe.status).toBe(400);
  });
});

describe('boss token management', () => {
  it('lists metadata without hashes or bearer values', async () => {
    const response = await SELF.fetch('http://localhost/api/boss/tokens', { headers: bossHeaders(TOKEN_MANAGEMENT_TOKEN) });
    expect(response.status).toBe(200);
    const data = await response.json() as { tokens: Array<Record<string, unknown>> };
    expect(data.tokens.length).toBeGreaterThan(0);
    expect(data.tokens[0]).not.toHaveProperty('token_hash');
    expect(data.tokens[0]).not.toHaveProperty('token');
  });

  it('revokes one own token', async () => {
    const { code } = await issueCode(TOKEN_MANAGEMENT_TOKEN);
    const redeemed = await SELF.fetch('http://localhost/api/pairing/redeem', {
      method: 'POST', body: JSON.stringify({ code, device_label: 'Revocable device' }),
    });
    const data = await redeemed.json() as { token: string };
    const tokenRow = await env.DB.prepare('SELECT id FROM boss_tokens WHERE token_hash = ?')
      .bind(await hashApiKey(data.token)).first<{ id: string }>();
    const response = await SELF.fetch(`http://localhost/api/boss/tokens/${tokenRow?.id}`, {
      method: 'DELETE', headers: bossHeaders(TOKEN_MANAGEMENT_TOKEN),
    });
    expect(response.status).toBe(200);
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders(data.token) })).status).toBe(401);
  });

  it('revokes every other token but keeps the requesting token', async () => {
    const { code } = await issueCode(TOKEN_MANAGEMENT_TOKEN);
    const redeemed = await SELF.fetch('http://localhost/api/pairing/redeem', {
      method: 'POST', body: JSON.stringify({ code, device_label: 'Other device' }),
    });
    const data = await redeemed.json() as { token: string };
    const response = await SELF.fetch('http://localhost/api/boss/tokens/revoke-others', {
      headers: bossHeaders(TOKEN_MANAGEMENT_TOKEN), method: 'POST',
    });
    expect(response.status).toBe(200);
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders(TOKEN_MANAGEMENT_TOKEN) })).status).toBe(200);
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders(data.token) })).status).toBe(401);
  });
});

describe('boss token authentication', () => {
  it('touches last_used_at and rejects a revoked token', async () => {
    const hash = await hashApiKey(BOSS_TOKEN);
    await env.DB.prepare('UPDATE boss_tokens SET last_used_at = NULL WHERE token_hash = ?').bind(hash).run();
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders() })).status).toBe(200);
    const used = await env.DB.prepare('SELECT id, last_used_at FROM boss_tokens WHERE token_hash = ?').bind(hash)
      .first<{ id: string; last_used_at: string | null }>();
    expect(used?.last_used_at).toBeTruthy();
    await env.DB.prepare("UPDATE boss_tokens SET revoked_at = datetime('now') WHERE id = ?").bind(used?.id).run();
    expect((await SELF.fetch('http://localhost/api/boss/me', { headers: bossHeaders() })).status).toBe(401);
  });
});
