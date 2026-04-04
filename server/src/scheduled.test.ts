// Tests for scheduled sweeps covering options expiry and queued delivery drain.
// Verifies SQL selection, queue state transitions, and error handling with fake D1.
// Depends on Vitest plus module mocks for delivery and expiry helpers.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { handleScheduled } from './scheduled';

function makeExpiryRow(id: string, agentId: string, opts: string[] = ['A', 'B']) {
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

function makeQueueRow(id: string, messageId: string, agentId: string, attempts = 0) {
  return {
    id,
    message_id: messageId,
    agent_id: agentId,
    channel: 'telegram' as const,
    config: JSON.stringify({ bot_token: 'token', chat_id: 'chat' }),
    scheduled_at: '2026-03-21T00:05:00Z',
    attempts,
  };
}

function makeQueuedMessage(id: string, agentId: string) {
  return {
    id,
    agent_id: agentId,
    direction: 'agent_to_boss',
    mode: 'async',
    channel: 'telegram',
    body: 'deliver later',
    status: 'sent',
    reply_to: null,
    priority: 'normal',
    type: 'text',
    target_agent_id: null,
    target_session_id: null,
    session_id: null,
    idempotency_key: null,
    metadata: JSON.stringify({ file_url: 'https://example.com/file.txt', options: ['A', 'B'] }),
    created_at: '2026-03-21T00:00:00Z',
    updated_at: '2026-03-21T00:00:00Z',
    agent_name: 'agent',
    avatar_url: null,
  };
}

function makeFakeEnv({
  expiryRows = [],
  queueRows = [],
  queuedMessages = {},
}: {
  expiryRows?: ReturnType<typeof makeExpiryRow>[];
  queueRows?: ReturnType<typeof makeQueueRow>[];
  queuedMessages?: Record<string, ReturnType<typeof makeQueuedMessage>>;
}) {
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
              if (sql.includes('expires_at IS NOT NULL')) {
                return {
                  all: async () => ({ results: expiryRows }),
                };
              }
              if (sql.includes('FROM delivery_queue') && sql.includes("status = 'pending'")) {
                return {
                  all: async () => ({ results: queueRows }),
                };
              }
              if (sql.startsWith("UPDATE delivery_queue SET status = 'pending', scheduled_at = ?")) {
                return {
                  run: async () => ({ success: true }),
                };
              }
              if (sql.startsWith("UPDATE delivery_queue SET status = 'pending' WHERE status = 'failed'")) {
                return {
                  run: async () => ({ success: true }),
                };
              }
              if (sql.startsWith("UPDATE delivery_queue SET status = 'processing'")) {
                return {
                  run: async () => ({ meta: { changes: 1 } }),
                };
              }
              if (sql.includes('FROM messages') && sql.includes('api_keys.name AS agent_name')) {
                return {
                  first: async () => queuedMessages[binds[0] as string] ?? null,
                };
              }
              return {
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

vi.mock('./routes/agent-delivery', () => ({
  deliverAgentMessage: vi.fn(async () => ({ delivered: true })),
}));

import { expireMessageOptions } from './routes/message-options';
import { deliverAgentMessage } from './routes/agent-delivery';

const mockedExpire = vi.mocked(expireMessageOptions);
const mockedDeliverAgentMessage = vi.mocked(deliverAgentMessage);

describe('handleScheduled', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-03-21T00:05:00.000Z'));
    mockedExpire.mockClear();
    mockedDeliverAgentMessage.mockClear();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('expires messages past their expires_at', async () => {
    const row1 = makeExpiryRow('msg-1', 'agent-a');
    const row2 = makeExpiryRow('msg-2', 'agent-b');
    const { env } = makeFakeEnv({ expiryRows: [row1, row2] });

    await handleScheduled(env as never);

    expect(mockedExpire).toHaveBeenCalledTimes(2);
    expect(mockedExpire).toHaveBeenCalledWith(env, 'agent-a', row1);
    expect(mockedExpire).toHaveBeenCalledWith(env, 'agent-b', row2);
  });

  it('does nothing when no expired messages', async () => {
    const { env } = makeFakeEnv({});

    await handleScheduled(env as never);

    expect(mockedExpire).not.toHaveBeenCalled();
  });

  it('continues processing when one message fails to expire', async () => {
    const row1 = makeExpiryRow('msg-fail', 'agent-a');
    const row2 = makeExpiryRow('msg-ok', 'agent-b');
    const { env } = makeFakeEnv({ expiryRows: [row1, row2] });

    mockedExpire.mockRejectedValueOnce(new Error('channel error'));

    await handleScheduled(env as never);

    expect(mockedExpire).toHaveBeenCalledTimes(2);
    expect(mockedExpire).toHaveBeenCalledWith(env, 'agent-b', row2);
  });

  it('drains due delivery queue items and updates the message', async () => {
    const queueRow = makeQueueRow('queue-1', 'queued-msg-1', 'agent-a');
    const queuedMessage = makeQueuedMessage('queued-msg-1', 'agent-a');
    const { env, preparedStatements } = makeFakeEnv({
      queueRows: [queueRow],
      queuedMessages: { 'queued-msg-1': queuedMessage },
    });

    mockedDeliverAgentMessage.mockResolvedValueOnce({ delivered: true, telegramMessageId: 42 });

    await handleScheduled(env as never);

    expect(mockedDeliverAgentMessage).toHaveBeenCalledTimes(1);
    expect(preparedStatements.some((stmt) => stmt.sql.startsWith("UPDATE delivery_queue SET status = 'processing'"))).toBe(true);
    expect(preparedStatements.some((stmt) => stmt.sql.startsWith("UPDATE messages SET status = 'delivered'"))).toBe(true);
    expect(preparedStatements.some((stmt) => stmt.sql.startsWith("UPDATE delivery_queue SET status = 'delivered'"))).toBe(true);
  });

  it('marks queued delivery as failed when channel delivery throws', async () => {
    const queueRow = makeQueueRow('queue-2', 'queued-msg-2', 'agent-b', 1);
    const queuedMessage = makeQueuedMessage('queued-msg-2', 'agent-b');
    const { env, preparedStatements } = makeFakeEnv({
      queueRows: [queueRow],
      queuedMessages: { 'queued-msg-2': queuedMessage },
    });

    mockedDeliverAgentMessage.mockRejectedValueOnce(new Error('channel error'));

    await handleScheduled(env as never);

    expect(preparedStatements.some((stmt) => stmt.sql.startsWith("UPDATE delivery_queue SET status = 'failed'"))).toBe(true);
    expect(preparedStatements.some((stmt) => stmt.sql.includes("json_set(COALESCE(metadata, '{}'), '$.delivery_error'"))).toBe(true);
    const failureUpdate = preparedStatements.find((stmt) => stmt.sql.startsWith("UPDATE delivery_queue SET status = 'failed'"));
    expect(failureUpdate?.binds[1]).toBe('2026-03-21T00:07:00.000Z');
  });

  it('queries expiry rows and pending queue rows with limits', async () => {
    const { env, preparedStatements } = makeFakeEnv({});

    await handleScheduled(env as never);

    const expiryQuery = preparedStatements.find((stmt) => stmt.sql.includes('expires_at IS NOT NULL'));
    const queueQuery = preparedStatements.find((stmt) => stmt.sql.includes('FROM delivery_queue'));

    expect(expiryQuery?.sql).toContain("json_extract(metadata, '$.options') IS NOT NULL");
    expect(expiryQuery?.binds[1]).toBe(50);
    expect(queueQuery?.sql).toContain("status = 'pending'");
    expect(queueQuery?.sql).toContain('scheduled_at <= ?');
    expect(queueQuery?.binds[1]).toBe(50);
  });

  it('reclaims stale processing rows and retries eligible failures before selecting pending work', async () => {
    const { env, preparedStatements } = makeFakeEnv({});

    await handleScheduled(env as never);

    const reclaimIndex = preparedStatements.findIndex((stmt) => stmt.sql.startsWith("UPDATE delivery_queue SET status = 'pending', scheduled_at = ?"));
    const retryIndex = preparedStatements.findIndex((stmt) => stmt.sql.startsWith("UPDATE delivery_queue SET status = 'pending' WHERE status = 'failed'"));
    const selectIndex = preparedStatements.findIndex((stmt) => stmt.sql.includes('FROM delivery_queue'));

    expect(reclaimIndex).toBeGreaterThan(-1);
    expect(retryIndex).toBeGreaterThan(-1);
    expect(selectIndex).toBeGreaterThan(retryIndex);
    expect(preparedStatements[reclaimIndex]?.binds[1]).toBe('2026-03-21T00:00:00.000Z');
    expect(preparedStatements[retryIndex]?.binds).toEqual([3, '2026-03-21T00:05:00.000Z']);
  });
});
