// Integration tests for auth middleware behavior and helpers.
// Verifies bearer authentication outcomes and hash consistency.
// Depends on cloudflare:test, test-helpers, and the middleware hash utility.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, authHeaders } from '../test-helpers';
import { apiAuth, bossAuth, dualAuth, hashApiKey } from './auth';

beforeAll(async () => {
  await seedDatabase();
});

describe('auth middleware integration', () => {
  it('returns 401 when no Authorization header', async () => {
    const res = await SELF.fetch('https://test.local/api/messages');
    expect(res.status).toBe(401);
  });

  it('returns 401 for invalid bearer token', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      headers: {
        Authorization: 'Bearer invalid-token',
      },
    });
    expect(res.status).toBe(401);
  });

  it('returns 401 for empty bearer token', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      headers: {
        Authorization: 'Bearer ',
      },
    });
    expect(res.status).toBe(401);
  });

  it('succeeds with valid bearer token', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);
    const data = await res.json() as { messages: unknown[]; total: number };
    expect(data.messages).toBeInstanceOf(Array);
  });

  it('updates last_used_at on successful auth', async () => {
    await env.DB.prepare('UPDATE api_keys SET last_used_at = NULL WHERE id = ?')
      .bind('test-agent-id')
      .run();
    const before = await env.DB.prepare('SELECT last_used_at FROM api_keys WHERE id = ?')
      .bind('test-agent-id')
      .first<{ last_used_at: string | null }>();
    expect(before).toBeDefined();
    expect(before?.last_used_at).toBeNull();

    const res = await SELF.fetch('https://test.local/api/messages', {
      headers: authHeaders(),
    });
    expect(res.status).toBe(200);

    const after = await env.DB.prepare('SELECT last_used_at FROM api_keys WHERE id = ?')
      .bind('test-agent-id')
      .first<{ last_used_at: string | null }>();
    expect(after).toBeDefined();
    expect(after?.last_used_at).toBeTruthy();
  });
});

describe('hashApiKey helper', () => {
  it('returns the same hash for identical input', async () => {
    const hashA = await hashApiKey('test-hash-key');
    const hashB = await hashApiKey('test-hash-key');
    expect(hashA).toBe(hashB);
  });

  it('returns different hashes for different input', async () => {
    const hashA = await hashApiKey('test-hash-key-a');
    const hashB = await hashApiKey('test-hash-key-b');
    expect(hashA).not.toBe(hashB);
  });
});

describe('auth activity writes', () => {
  it('does not wait for api key activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(apiAuth, { id: 'agent-id' });
  });

  it('does not wait for boss token activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(bossAuth, {
      id: 'boss-id', name: 'Boss', role: 'admin', token_id: 'token-id',
    });
  });

  it('does not wait for dual agent activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(dualAuth, { id: 'agent-id' });
  });

  it('does not wait for dual boss activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(dualAuth, null, {
      id: 'boss-id', name: 'Boss', role: 'admin', token_id: 'token-id',
    });
  });
});

async function assertAuthWriteIsDeferred(
  authenticate: typeof apiAuth,
  ...records: (Record<string, string> | null)[]
): Promise<void> {
  let releaseUpdate: () => void = () => {};
  const update = new Promise<unknown>((resolve) => { releaseUpdate = () => resolve({}); });
  const waits: Promise<unknown>[] = [];
  let selectIndex = 0;
  const db = {
    prepare(sql: string) {
      return {
        bind(..._values: unknown[]) {
          if (sql.startsWith('SELECT')) {
            return { first: async <T>(): Promise<T | null> => records[selectIndex++] as T | null };
          }
          return { run: () => update };
        },
      };
    },
  };
  const context = {
    req: { header: () => 'Bearer test-token' },
    env: { DB: db },
    executionCtx: { waitUntil: (promise: Promise<unknown>) => waits.push(promise) },
    text: (body: string, status: number) => new Response(body, { status }),
  } as unknown as Parameters<typeof apiAuth>[0];
  let handlerCalled = false;
  const response = await authenticate(context, async () => {
    handlerCalled = true;
  });

  expect(response).toBeUndefined();
  expect(handlerCalled).toBe(true);
  expect(waits).toHaveLength(1);
  releaseUpdate();
  await waits[0];
}
