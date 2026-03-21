// Tests for the scheduled options expiry sweep handler.
// Verifies that handleScheduled queries expired messages and calls expireMessageOptions.
// Uses fake DB to isolate from real D1.

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { handleScheduled } from './scheduled';

function makeRow(id: string, agentId: string, opts: string[] = ['A', 'B']) {
  return {
    id,
    agent_id: agentId,
    direction: 'agent_to_boss',
    mode: 'blocking',
    channel: 'telegram',
    body: 'pick one',
    status: 'delivered',
    metadata: JSON.stringify({ options: opts }),
    created_at: '2026-03-21T00:00:00Z',
    updated_at: '2026-03-21T00:00:00Z',
    expires_at: '2026-03-21T00:05:00Z',
  };
}

function makeFakeEnv(rows: ReturnType<typeof makeRow>[]) {
  const preparedStatements: { sql: string; binds: unknown[] }[] = [];
  return {
    env: {
      DB: {
        prepare(sql: string) {
          const stmt = { sql, binds: [] as unknown[] };
          preparedStatements.push(stmt);
          return {
            bind(...binds: unknown[]) {
              stmt.binds = binds;
              return {
                all: async () => ({ results: rows }),
                run: async () => ({ success: true }),
              };
            },
          };
        },
      },
    },
    preparedStatements,
  };
}

// Mock expireMessageOptions to track calls
vi.mock('./routes/message-options', () => ({
  expireMessageOptions: vi.fn(async () => {}),
}));

import { expireMessageOptions } from './routes/message-options';
const mockedExpire = vi.mocked(expireMessageOptions);

describe('handleScheduled', () => {
  beforeEach(() => {
    mockedExpire.mockClear();
  });

  it('expires messages past their expires_at', async () => {
    const row1 = makeRow('msg-1', 'agent-a');
    const row2 = makeRow('msg-2', 'agent-b');
    const { env } = makeFakeEnv([row1, row2]);

    await handleScheduled(env as any);

    expect(mockedExpire).toHaveBeenCalledTimes(2);
    expect(mockedExpire).toHaveBeenCalledWith(env, 'agent-a', row1);
    expect(mockedExpire).toHaveBeenCalledWith(env, 'agent-b', row2);
  });

  it('does nothing when no expired messages', async () => {
    const { env } = makeFakeEnv([]);

    await handleScheduled(env as any);

    expect(mockedExpire).not.toHaveBeenCalled();
  });

  it('continues processing when one message fails to expire', async () => {
    const row1 = makeRow('msg-fail', 'agent-a');
    const row2 = makeRow('msg-ok', 'agent-b');
    const { env } = makeFakeEnv([row1, row2]);

    mockedExpire.mockRejectedValueOnce(new Error('channel error'));

    await handleScheduled(env as any);

    expect(mockedExpire).toHaveBeenCalledTimes(2);
    // Second call should still happen despite first failure
    expect(mockedExpire).toHaveBeenCalledWith(env, 'agent-b', row2);
  });

  it('queries with correct SQL shape', async () => {
    const { env, preparedStatements } = makeFakeEnv([]);

    await handleScheduled(env as any);

    expect(preparedStatements).toHaveLength(1);
    const query = preparedStatements[0];
    expect(query.sql).toContain('expires_at IS NOT NULL');
    expect(query.sql).toContain('expires_at < ?');
    expect(query.sql).toContain("status IN ('sent', 'delivered', 'read')");
    expect(query.sql).toContain("json_extract(metadata, '$.options') IS NOT NULL");
    expect(query.sql).toContain('LIMIT ?');
    // First bind is ISO timestamp (now), second is batch size
    expect(typeof query.binds[0]).toBe('string');
    expect(query.binds[1]).toBe(50);
  });
});
