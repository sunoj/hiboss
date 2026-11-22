// Integration tests for auth middleware behavior and helpers.
// Verifies bearer authentication outcomes and hash consistency.
// Depends on cloudflare:test, test-helpers, and the middleware hash utility.

import { testRequest, returnsStatus, testJson } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, seedBossToken, authHeaders } from '../test-helpers';
import { apiAuth, bossAuth, dualAuth, hashApiKey } from './auth';

const BOSS_TOKEN = 'hb_boss_auth_usage_stamp_token_0001';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Usage Stamp Boss', 'admin', BOSS_TOKEN, 'usage-stamp-boss');
});

describe('auth middleware integration', () => {
  it('returns 401 when no Authorization header', returnsStatus(401, () =>
    SELF.fetch('https://test.local/api/messages')));

  it('returns 401 for invalid bearer token', returnsStatus(401, () =>
    testRequest('GET', 'https://test.local/api/messages', {
        Authorization: 'Bearer invalid-token',
      })));

  it('returns 401 for empty bearer token', returnsStatus(401, () =>
    testRequest('GET', 'https://test.local/api/messages', {
        Authorization: 'Bearer ',
      })));

  it('succeeds with valid bearer token', async () => {
    const data = await testJson(200, testRequest('GET', 'https://test.local/api/messages', authHeaders())
    ) as { messages: unknown[]; total: number };
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

    const res = await testRequest('GET', 'https://test.local/api/messages', authHeaders());
    expect(res.status).toBe(200);

    const after = await env.DB.prepare('SELECT last_used_at FROM api_keys WHERE id = ?')
      .bind('test-agent-id')
      .first<{ last_used_at: string | null }>();
    expect(after).toBeDefined();
    expect(after?.last_used_at).toBeTruthy();
  });

  it.each([
    ['api_keys', 'id', 'test-agent-id', () => authHeaders()],
    ['boss_tokens', 'boss_id', 'usage-stamp-boss', () => ({ Authorization: `Bearer ${BOSS_TOKEN}` })],
  ] as const)('writes %s.last_used_at at most once a minute', async (table, column, owner, headers) => {
    const stamp = async () => (await env.DB.prepare(`SELECT last_used_at FROM ${table} WHERE ${column} = ?`)
      .bind(owner).first<{ last_used_at: string | null }>())?.last_used_at;
    const path = table === 'api_keys' ? '/api/messages' : '/api/boss/me';
    const request = async () => expect((await SELF.fetch(`http://localhost${path}`, { headers: headers() })).status).toBe(200);
    await env.DB.prepare(`UPDATE ${table} SET last_used_at = datetime('now', '-10 seconds') WHERE ${column} = ?`).bind(owner).run();
    const recent = await stamp();
    await request();
    expect(await stamp()).toBe(recent);
    await env.DB.prepare(`UPDATE ${table} SET last_used_at = datetime('now', '-2 minutes') WHERE ${column} = ?`).bind(owner).run();
    const stale = await stamp();
    await request();
    expect(await stamp()).not.toBe(stale);
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

// The lookups report a stale usage stamp, so each request owes exactly one deferred write.
describe('auth activity writes', () => {
  it('does not wait for api key activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(apiAuth, { id: 'agent-id', agent_stale: 1 });
  });

  it('does not wait for boss token activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(bossAuth, {
      id: 'boss-id', name: 'Boss', role: 'admin', token_id: 'token-id', token_stale: 1,
    });
  });

  it('does not wait for dual agent activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(dualAuth, { id: 'agent-id', agent_stale: 1 });
  });

  it('does not wait for dual boss activity persistence before the handler', async () => {
    await assertAuthWriteIsDeferred(dualAuth, null, {
      id: 'boss-id', name: 'Boss', role: 'admin', token_id: 'token-id', token_stale: 1,
    });
  });
});

async function assertAuthWriteIsDeferred(
  authenticate: typeof apiAuth,
  ...records: (Record<string, string | number> | null)[]
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
