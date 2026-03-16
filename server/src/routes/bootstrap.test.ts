// Integration tests for /api/bootstrap endpoint.
// Depends on cloudflare:test env and the bootstrap route behavior.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
});

describe('POST /api/bootstrap', () => {
  it('returns 403 when api_keys already has entries and no auth is provided', async () => {
    const countRow = await env.DB
      .prepare('SELECT COUNT(*) AS count FROM api_keys')
      .first<{ count: number }>();
    expect(countRow?.count ?? 0).toBeGreaterThan(0);

    const res = await SELF.fetch('https://test.local/api/bootstrap', {
      method: 'POST',
    });

    expect(res.status).toBe(403);
  });
});
