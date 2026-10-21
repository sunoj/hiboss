// Registration API tests: create, one row per APNs token, token rotation, deletion, validation
// and no-oracle.

import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import { TOKEN_A, TOKEN_B, apnsCalls, call, countRows, mockApns, pushBody, register, resetDb } from './helpers';

beforeEach(async () => {
  await resetDb();
  mockApns();
});
afterEach(() => vi.unstubAllGlobals());

describe('POST /v1/registrations', () => {
  it('mints a 32-byte handle and deviceSecret and stores only their SHA-256', async () => {
    const { handle, deviceSecret } = await register();
    expect(handle).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(deviceSecret).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(handle).not.toBe(deviceSecret);
    const rows = await env.DB.prepare('SELECT * FROM registrations').all<Record<string, unknown>>();
    expect(rows.results).toHaveLength(1);
    const row = rows.results[0];
    expect(row.handle_hash).toBe(await sha256Hex(handle));
    expect(row.secret_hash).toBe(await sha256Hex(deviceSecret));
    const stored = JSON.stringify(rows.results);
    expect(stored).not.toContain(handle);
    expect(stored).not.toContain(deviceSecret);
  });

  it.each([
    ['unknown field', { apnsToken: TOKEN_A, environment: 'production', bundleId: 'x.evil' }],
    ['bad environment', { apnsToken: TOKEN_A, environment: 'staging' }],
    ['non-hex token', { apnsToken: 'z'.repeat(64), environment: 'production' }],
    ['short token', { apnsToken: 'a'.repeat(63), environment: 'production' }],
    ['missing token', { environment: 'sandbox' }],
    ['array body', [TOKEN_A]],
  ])('rejects %s with 400', async (_name, body) => {
    const response = await call('POST', '/v1/registrations', { body });
    expect(response.status).toBe(400);
    expect(await countRows('registrations')).toBe(0);
  });

  it('rejects invalid JSON and oversized bodies with 400', async () => {
    expect((await call('POST', '/v1/registrations', { raw: '{nope' })).status).toBe(400);
    const big = JSON.stringify({ apnsToken: TOKEN_A, environment: 'production', pad: 'x'.repeat(9000) });
    expect((await call('POST', '/v1/registrations', { raw: big })).status).toBe(400);
  });

  it('rejects plain HTTP', async () => {
    const response = await call('POST', '/v1/registrations', {
      body: { apnsToken: TOKEN_A, environment: 'production' },
      url: 'http://push.test',
    });
    expect(response.status).toBe(403);
    expect(await countRows('registrations')).toBe(0);
  });
});

describe('one registration per APNs token', () => {
  it('re-registering a token kills the old handle and secret and keeps one row', async () => {
    const fetchMock = mockApns();
    const old = await register(TOKEN_A, 'production');
    const fresh = await register(TOKEN_A, 'sandbox');
    expect(await countRows('registrations')).toBe(1);
    expect((await call('POST', '/v1/push', { body: pushBody(old.handle) })).status).toBe(410);
    const body = { apnsToken: TOKEN_B, environment: 'production' };
    expect((await call('PUT', '/v1/registrations/self', { body, secret: old.deviceSecret })).status).toBe(410);
    expect((await call('POST', '/v1/push', { body: pushBody(fresh.handle) })).status).toBe(202);
    const alerts = apnsCalls(fetchMock, 'alert');
    expect(alerts).toHaveLength(1);
    expect(alerts[0][0]).toBe(`https://api.sandbox.push.apple.com/3/device/${TOKEN_A}`);
  });

  it('rotating to a token another registration holds replaces that registration', async () => {
    mockApns();
    const holder = await register(TOKEN_B);
    const mover = await register(TOKEN_A);
    const body = { apnsToken: TOKEN_B.toUpperCase(), environment: 'production' };
    expect((await call('PUT', '/v1/registrations/self', { body, secret: mover.deviceSecret })).status).toBe(204);
    const rows = await env.DB.prepare('SELECT handle_hash, apns_token FROM registrations').all();
    expect(rows.results).toEqual([{ handle_hash: await sha256Hex(mover.handle), apns_token: TOKEN_B }]);
    expect((await call('POST', '/v1/push', { body: pushBody(holder.handle) })).status).toBe(410);
    expect((await call('POST', '/v1/push', { body: pushBody(mover.handle) })).status).toBe(202);
  });

  it('rotating to the token a registration already holds keeps it', async () => {
    const { handle, deviceSecret } = await register(TOKEN_A);
    const body = { apnsToken: TOKEN_A, environment: 'sandbox' };
    expect((await call('PUT', '/v1/registrations/self', { body, secret: deviceSecret })).status).toBe(204);
    expect(await countRows('registrations')).toBe(1);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
  });
});

describe('PUT /v1/registrations/self', () => {
  it('rotates the APNs token and keeps the handle', async () => {
    const fetchMock = mockApns();
    const { handle, deviceSecret } = await register(TOKEN_A, 'production');
    const put = await call('PUT', '/v1/registrations/self', {
      secret: deviceSecret,
      body: { apnsToken: TOKEN_B.toUpperCase(), environment: 'sandbox' },
    });
    expect(put.status).toBe(204);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(202);
    expect(apnsCalls(fetchMock, 'alert')[0][0]).toBe(`https://api.sandbox.push.apple.com/3/device/${TOKEN_B}`);
  });

  it('answers wrong, missing and malformed secrets exactly like an unknown one', async () => {
    await register();
    const body = { apnsToken: TOKEN_B, environment: 'production' };
    const attempts = [
      await call('PUT', '/v1/registrations/self', { body, secret: 'A'.repeat(43) }),
      await call('PUT', '/v1/registrations/self', { body }),
      await call('PUT', '/v1/registrations/self', { body, secret: 'not a secret' }),
    ];
    const seen = await Promise.all(attempts.map(async (r) => `${r.status} ${await r.text()}`));
    expect(new Set(seen).size).toBe(1);
    expect(seen[0]).toBe('410 {"error":"gone"}');
    const row = await env.DB.prepare('SELECT apns_token FROM registrations').first<{ apns_token: string }>();
    expect(row?.apns_token).toBe(TOKEN_A);
  });

  it('rejects an invalid body with 400 even with a valid secret', async () => {
    const { deviceSecret } = await register();
    const response = await call('PUT', '/v1/registrations/self', {
      secret: deviceSecret,
      body: { apnsToken: TOKEN_B, environment: 'production', handle: 'x' },
    });
    expect(response.status).toBe(400);
  });
});

describe('DELETE /v1/registrations/self', () => {
  it('deletes the registration, after which pushes get 410, and is idempotent', async () => {
    const { handle, deviceSecret } = await register();
    expect((await call('DELETE', '/v1/registrations/self', { secret: deviceSecret })).status).toBe(204);
    expect(await countRows('registrations')).toBe(0);
    expect((await call('DELETE', '/v1/registrations/self', { secret: deviceSecret })).status).toBe(204);
    expect((await call('POST', '/v1/push', { body: pushBody(handle) })).status).toBe(410);
  });

  it('answers an unknown or missing secret with the same 204 and deletes nothing', async () => {
    await register();
    expect((await call('DELETE', '/v1/registrations/self', { secret: 'B'.repeat(43) })).status).toBe(204);
    expect((await call('DELETE', '/v1/registrations/self')).status).toBe(204);
    expect(await countRows('registrations')).toBe(1);
  });

  it('only deletes the registration that owns the secret', async () => {
    const first = await register(TOKEN_A);
    const second = await register(TOKEN_B);
    await call('DELETE', '/v1/registrations/self', { secret: first.deviceSecret });
    expect((await call('POST', '/v1/push', { body: pushBody(second.handle) })).status).toBe(202);
  });
});

describe('routing', () => {
  it('returns 404 JSON for unknown paths', async () => {
    const response = await call('GET', '/v1/registrations');
    expect(response.status).toBe(404);
  });
});
