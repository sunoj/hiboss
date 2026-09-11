// Message API regression suites extracted to keep each file bounded.
// Registers cases in messages.test.ts; depends on its shared database setup.
import { SELF } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId } from '../../test-helpers';
import { insertMessageWithRecovery } from '../messages';
import { buildStreamQuery, pruneSeenMessageIds } from '../stream';
import type { Env, MessageRow } from '../../types';

function raceEnvironment(existing: Record<string, unknown>): Env {
    const fakeEnv = {
      DB: {
        prepare(sql: string) {
          if (sql.startsWith('INSERT INTO messages')) {
            return {
              bind() {
                return {
                  first: async () => { throw new Error('UNIQUE constraint failed: messages.agent_id, messages.idempotency_key'); },
                };
              },
            };
          }
          if (sql === 'SELECT * FROM messages WHERE agent_id = ? AND idempotency_key = ?') {
            return {
              bind() {
                return {
                  first: async () => existing,
                };
              },
            };
          }
          throw new Error(`unexpected SQL: ${sql}`);
        },
      },
    };
  return fakeEnv as unknown as Env;
}

describe('POST /api/messages idempotency', () => {
  it('returns 201 on first send with idempotency_key', async () => {
    const res = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'test', idempotency_key: 'key-1' }),
    });
    expect(res.status).toBe(201);
    const data = await res.json() as Record<string, unknown>;
    expect(data.id).toBeDefined();
  });

  it('returns 200 with same id on duplicate idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'first', idempotency_key: 'dup-key' }),
    });
    expect(res1.status).toBe(201);
    const data1 = await res1.json() as Record<string, unknown>;
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'second', idempotency_key: 'dup-key' }),
    });
    expect(res2.status).toBe(200);
    const data2 = await res2.json() as Record<string, unknown>;
    expect(data2.id).toBe(data1.id);
  });

  it('creates new message with different idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'a', idempotency_key: 'key-a' }),
    });
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'b', idempotency_key: 'key-b' }),
    });
    expect(res1.status).toBe(201);
    expect(res2.status).toBe(201);
    const d1 = await res1.json() as Record<string, unknown>;
    const d2 = await res2.json() as Record<string, unknown>;
    expect(d1.id).not.toBe(d2.id);
  });

  it('always creates new message without idempotency_key', async () => {
    const res1 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'no key 1' }),
    });
    const res2 = await SELF.fetch('https://test.local/api/messages', {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify({ body: 'no key 2' }),
    });
    expect(res1.status).toBe(201);
    expect(res2.status).toBe(201);
    const d1 = await res1.json() as Record<string, unknown>;
    const d2 = await res2.json() as Record<string, unknown>;
    expect(d1.id).not.toBe(d2.id);
  });

  it('returns existing message when insert hits unique constraint', async () => {
    const existing = {
      id: 'race-msg-001',
      agent_id: getTestAgentId(),
      direction: 'agent_to_boss',
      mode: 'async',
      channel: 'api',
      body: 'first',
      status: 'sent',
      reply_to: null,
      priority: 'normal',
      type: 'text',
      target_agent_id: null,
      target_session_id: null,
      session_id: null,
      idempotency_key: 'race-key',
      metadata: null,
      created_at: '2026-01-01T00:00:00Z',
      updated_at: '2026-01-01T00:00:00Z',
    };
    const fakeEnv = raceEnvironment(existing);
    const result = await insertMessageWithRecovery(fakeEnv, getTestAgentId(), [
      'agent_to_boss',
      'async',
      'api',
      'second',
      'normal',
      'text',
      'race-key',
      null,
      null,
      null,
      null,
    ]);
    expect(result.inserted).toBeNull();
    expect(result.existing).toEqual(existing);
  });
});

describe('stream helpers', () => {
  it('uses >= in the polling query', () => {
    const { sql } = buildStreamQuery(getTestAgentId());
    expect(sql).toContain('messages.created_at >= ?');
  });

  it('retains seen ids for the same timestamp batch and clears them after the window advances', () => {
    const seen = new Set<string>(['m1']);
    pruneSeenMessageIds(seen, [{ id: 'm2', created_at: '2026-01-01 00:00:00' } as MessageRow], '2026-01-01 00:00:00');
    expect(seen.has('m1')).toBe(true);

    pruneSeenMessageIds(seen, [{ id: 'm3', created_at: '2026-01-01 00:00:01' } as MessageRow], '2026-01-01 00:00:00');
    expect(seen.size).toBe(0);
  });
});
