// Integration tests for /api/bootstrap endpoint.
// Depends on cloudflare:test env and the bootstrap route behavior.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase } from '../test-helpers';

const BOOTSTRAP_URL = 'https://test.local/api/bootstrap';
const BOOTSTRAP_SECRET = 'bootstrap-secret';

beforeAll(async () => {
  await seedDatabase();
});

describe('POST /api/bootstrap', () => {
  it('returns 403 when api_keys already has entries and no auth is provided', async () => {
    const countRow = await env.DB
      .prepare('SELECT COUNT(*) AS count FROM api_keys')
      .first<{ count: number }>();
    expect(countRow?.count ?? 0).toBeGreaterThan(0);

    const res = await SELF.fetch(BOOTSTRAP_URL, {
      method: 'POST',
    });

    expect(res.status).toBe(403);
  });

  it('rejects requests without the bootstrap secret when configured', async () => {
    env.BOOTSTRAP_SECRET = BOOTSTRAP_SECRET;

    const res = await SELF.fetch(BOOTSTRAP_URL, {
      method: 'POST',
    });

    expect(res.status).toBe(401);
    expect(await res.text()).toBe('unauthorized');
    env.BOOTSTRAP_SECRET = undefined;
  });

  it('allows only one successful bootstrap when starting from an empty table', async () => {
    await resetApiKeys();
    env.BOOTSTRAP_SECRET = BOOTSTRAP_SECRET;

    const first = await SELF.fetch(BOOTSTRAP_URL, {
      method: 'POST',
      headers: { Authorization: `Bearer ${BOOTSTRAP_SECRET}` },
    });
    const second = await SELF.fetch(BOOTSTRAP_URL, {
      method: 'POST',
      headers: { 'X-Bootstrap-Secret': BOOTSTRAP_SECRET },
    });

    expect(first.status).toBe(201);
    expect(second.status).toBe(403);

    const countRow = await env.DB
      .prepare('SELECT COUNT(*) AS count FROM api_keys')
      .first<{ count: number }>();
    expect(countRow?.count).toBe(1);

    await resetApiKeys();
    env.BOOTSTRAP_SECRET = undefined;
  });
});

async function resetApiKeys(): Promise<void> {
  await env.DB.prepare('DELETE FROM api_keys').run();
}
