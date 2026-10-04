// Tests the limits on "Sign in with iPhone": the code attempt limit, expiry, a revoked
// approving token, signing registrations and the open-request cap.
// Depends on cloudflare:test, test-helpers and ./test-support.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';
import { approvedCode, complete, open, registration, status, act } from './test-support';
import { MAX_CODE_ATTEMPTS, MAX_OPEN_REQUESTS } from './store';

const ADMIN = 'hb_boss_signin_guard_admin_0000001';
const SECOND = 'hb_boss_signin_guard_second_000001';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Guard Admin', 'admin', ADMIN);
  await seedBossToken('Guard Second', 'admin', SECOND);
});

function wrong(code: string): string {
  return code === '000000' ? '000001' : '000000';
}

describe('sign-in limits', () => {
  it('rejects the request after the last allowed wrong code', async () => {
    const opened = await open();
    const code = await approvedCode(opened.request_id, ADMIN);
    for (let i = 0; i < MAX_CODE_ATTEMPTS; i++) {
      expect((await complete(opened.poll_token, { code: wrong(code) })).status).toBe(400);
    }
    expect(await (await status(opened.poll_token)).json()).toMatchObject({ status: 'rejected' });
    expect((await complete(opened.poll_token, { code })).status).toBe(400);
  });

  it('refuses an expired request on both sides', async () => {
    const opened = await open();
    const code = await approvedCode(opened.request_id, ADMIN);
    await env.DB.prepare("UPDATE signin_requests SET expires_at = '2000-01-01T00:00:00.000Z' WHERE id = ?").bind(opened.request_id).run();
    expect(await (await status(opened.poll_token)).json()).toMatchObject({ status: 'expired' });
    expect((await complete(opened.poll_token, { code })).status).toBe(400);
    const pending = await open();
    await env.DB.prepare("UPDATE signin_requests SET expires_at = '2000-01-01T00:00:00.000Z' WHERE id = ?").bind(pending.request_id).run();
    expect((await act(pending.request_id, 'approve', ADMIN)).status).toBe(409);
  });

  it('refuses completion once the approving token is revoked', async () => {
    const opened = await open();
    const code = await approvedCode(opened.request_id, SECOND);
    await env.DB.prepare("UPDATE boss_tokens SET revoked_at = datetime('now') WHERE id = (SELECT approved_by_token_id FROM signin_requests WHERE id = ?)")
      .bind(opened.request_id).run();
    expect((await complete(opened.poll_token, { code })).status).toBe(400);
  });
});

describe('sign-in signing registration', () => {
  it('registers a macos client key proven over the request id', async () => {
    const opened = await open('Signed Mac');
    const code = await approvedCode(opened.request_id, ADMIN);
    const signing = await registration('hiboss-signin-v1', opened.request_id);
    const res = await complete(opened.poll_token, { code, signing });
    expect(res.status).toBe(200);
    const grant = await res.json() as { signing_key_id?: string };
    expect(grant.signing_key_id).toBeTruthy();
    const client = await env.DB.prepare("SELECT kind FROM boss_clients WHERE label = 'Signed Mac'").first<{ kind: string }>();
    expect(client?.kind).toBe('macos');
  });

  it('refuses a pairing-domain proof and keeps the request usable', async () => {
    const opened = await open();
    const code = await approvedCode(opened.request_id, ADMIN);
    const signing = await registration('hiboss-pair-v1', opened.request_id);
    expect((await complete(opened.poll_token, { code, signing })).status).toBe(400);
    expect((await complete(opened.poll_token, { code })).status).toBe(200);
  });
});

describe('sign-in housekeeping', () => {
  it('caps open requests and reclaims expired ones on the next open', async () => {
    const statements = Array.from({ length: MAX_OPEN_REQUESTS }, (_, i) => env.DB.prepare(
      "INSERT INTO signin_requests (id, poll_token_hash, device_label, created_at, expires_at) VALUES (?, ?, 'filler', '2000-01-01', '2999-01-01')",
    ).bind(`filler-${i}`, `filler-hash-${i}`));
    await env.DB.batch(statements);
    const res = await SELF.fetch('http://localhost/api/signin/requests', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ device_label: 'Mac' }),
    });
    expect(res.status).toBe(429);
    await env.DB.prepare("UPDATE signin_requests SET expires_at = '2000-01-01T00:00:00.000Z' WHERE id LIKE 'filler-%'").run();
    expect((await open()).request_id).toMatch(/^[0-9a-f]{32}$/);
    const left = await env.DB.prepare("SELECT COUNT(*) AS n FROM signin_requests WHERE id LIKE 'filler-%'").first<{ n: number }>();
    expect(left?.n).toBe(0);
  });
});
