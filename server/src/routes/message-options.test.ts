// Tests for message option expiry and default auto-selection.
// Covers server-side option timeout behavior with D1-backed message rows.
// Depends on cloudflare:test fixtures, message option helpers, and mocked callbacks.

import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Env, MessageRow } from '../types';
import { seedDatabase, getTestAgentId } from '../test-helpers';
import { expireMessageOptions } from './message-options';
import { notifyAgentCallback } from '../notify';

vi.mock('../notify', () => ({
  notifyAgentCallback: vi.fn(async () => {}),
}));

const mockedNotifyAgentCallback = vi.mocked(notifyAgentCallback);

beforeAll(async () => {
  await seedDatabase();
});

beforeEach(() => {
  mockedNotifyAgentCallback.mockClear();
});

describe('expireMessageOptions default option handling', () => {
  it('auto-resolves with the default option after expiry', async () => {
    const message = await insertOptionMessage('default', {
      options: ['A', 'B'],
      default_option: 'A',
    });

    await expireMessageOptions(env as Env, message.agent_id, message);

    const original = await fetchMessage(message.id);
    expect(original?.status).toBe('replied');
    expect(parseMetadata(original?.metadata)['options_expired']).toBe(true);

    const reply = await fetchReply(message.id);
    expect(reply?.direction).toBe('boss_to_agent');
    expect(reply?.body).toBe('A');
    expect(reply?.mode).toBe('async');
    expect(reply?.channel).toBe('api');
    expect(reply?.status).toBe('sent');
    expect(parseMetadata(reply?.metadata)['auto_default']).toBe(true);
    expect(mockedNotifyAgentCallback).toHaveBeenCalledTimes(1);
    const callbackArgs = mockedNotifyAgentCallback.mock.calls[0];
    expect(callbackArgs?.[1]).toBe(message.agent_id);
    expect(callbackArgs?.[2]).toMatchObject({ id: reply?.id, body: 'A', reply_to: message.id });
  });

  it('expires option messages that have no default option', async () => {
    const message = await insertOptionMessage('no-default', {
      options: ['A', 'B'],
    });

    await expireMessageOptions(env as Env, message.agent_id, message);

    const original = await fetchMessage(message.id);
    expect(original?.status).toBe('expired');
    expect(parseMetadata(original?.metadata)['options_expired']).toBe(true);
    expect(await fetchReply(message.id)).toBeNull();
    expect(mockedNotifyAgentCallback).not.toHaveBeenCalled();
  });

  it('expires when default_option is not one of the offered options', async () => {
    const message = await insertOptionMessage('invalid-default', {
      options: ['A', 'B'],
      default_option: 'C',
    });

    await expireMessageOptions(env as Env, message.agent_id, message);

    const original = await fetchMessage(message.id);
    expect(original?.status).toBe('expired');
    expect(await fetchReply(message.id)).toBeNull();
    expect(mockedNotifyAgentCallback).not.toHaveBeenCalled();
  });
});

async function insertOptionMessage(label: string, metadata: Record<string, unknown>): Promise<MessageRow> {
  const id = `option-expiry-${label}-${crypto.randomUUID()}`;
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at) VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Choose', 'delivered', 'normal', ?, ?)"
  ).bind(id, getTestAgentId(), JSON.stringify(metadata), '2026-01-01T00:00:00.000Z').run();
  const row = await fetchMessage(id);
  if (!row) throw new Error('failed to insert option message');
  return row;
}

async function fetchMessage(id: string): Promise<MessageRow | null> {
  return env.DB.prepare('SELECT * FROM messages WHERE id = ?')
    .bind(id)
    .first<MessageRow>();
}

async function fetchReply(replyTo: string): Promise<MessageRow | null> {
  return env.DB.prepare('SELECT * FROM messages WHERE reply_to = ?')
    .bind(replyTo)
    .first<MessageRow>();
}

function parseMetadata(metadata: string | null | undefined): Record<string, unknown> {
  return metadata ? JSON.parse(metadata) as Record<string, unknown> : {};
}
