// Real D1 queries for messages, replies, channel configuration and session state.
// Preserves the named message-helper regression scenarios.
// Depends on Vitest and message helpers with Cloudflare D1.

import { describe, expect, it, beforeAll } from 'vitest';
import { agentId, rateAgentId, msgId, parentId, sessId, seedMessageQueries, testEnv } from './fixtures';
import {
  selectChannelConfig,
  fetchMessageRow,
  fetchReplies,
  fetchMessageWithReplies,
  fetchAgentName,
  fetchAllChannelConfigs,
  checkRateLimit,
  findByIdempotencyKey,
  inferSessionStatus,
} from '../message-helpers';

beforeAll(seedMessageQueries);

describe('selectChannelConfig', () => {
  it.each([
    ['returns exact requested channel', 'telegram', {
      channel: 'telegram', config: { chat_id: 'tg-123', bot_token: 'tg-tok' },
    }],
    ['falls back to most recent when requested channel not found', 'api', { channel: 'discord' }],
    ['falls back to most recent when no channel requested', undefined, { channel: 'discord' }],
  ] as const)('%s', async (_name, requested, expected) => {
    // Discord was inserted with later created_at, so it should be the fallback.
    const result = await selectChannelConfig(testEnv, agentId, requested);
    expect(result.channel).toBe(expected.channel);
    if ('config' in expected) {
      expect(result.config).toEqual(expected.config);
    }
  });

  it('throws when agent has no channels', async () => {
    await expect(selectChannelConfig(testEnv, 'no-such-agent')).rejects.toThrow('no channel configured');
  });
});

describe('fetchMessageRow', () => {
  it.each([
    ['returns exact match by full ID', agentId, msgId, { id: msgId, body: 'fetch test body' }],
    ['returns prefix match by short ID', agentId, 'fetch-ms', { id: msgId }],
    ['returns null for non-existent ID', agentId, 'nonexistent-id-999', null],
    ['returns null for wrong agent', 'other-agent', msgId, null],
    ['joins agent_name from api_keys', agentId, msgId, { agent_name: 'test-agent' }],
  ] as const)('%s', async (_name, owner, id, expected) => {
    const row = await fetchMessageRow(testEnv, owner, id);
    if (expected === null) {
      expect(row).toBeNull();
    } else {
      expect(row).toMatchObject(expected);
    }
  });
});

describe('fetchReplies', () => {
  it('returns replies ordered by created_at ASC', async () => {
    const replies = await fetchReplies(testEnv, parentId);
    expect(replies).toHaveLength(2);
    expect(replies[0].body).toBe('reply 1');
    expect(replies[1].body).toBe('reply 2');
  });

  it('returns parsed metadata in replies', async () => {
    const replies = await fetchReplies(testEnv, parentId);
    // Parse the populated reply while preserving null for the reply without metadata.
    expect(replies.map((reply) => reply.metadata)).toEqual([{ answer: 'Yes' }, null]);
  });

  it('returns empty array for message with no replies', async () => {
    const replies = await fetchReplies(testEnv, 'no-replies-parent');
    expect(replies).toEqual([]);
  });
});

describe('fetchMessageWithReplies', () => {
  it('returns message with replies array', async () => {
    const result = await fetchMessageWithReplies(testEnv, agentId, 'reply-parent-001');
    expect(result).not.toBeNull();
    expect(result!.id).toBe('reply-parent-001');
    expect(result!.replies.map((reply) => reply.id)).toEqual(['reply-child-001', 'reply-child-002']);
  });

  it('returns null for non-existent message', async () => {
    const result = await fetchMessageWithReplies(testEnv, agentId, 'no-such-msg');
    expect(result).toBeNull();
  });

  it('returns message with empty replies when no children exist', async () => {
    // fetch-msg-test-001 has no replies
    const result = await fetchMessageWithReplies(testEnv, agentId, 'fetch-msg-test-001');
    expect(result).not.toBeNull();
    expect(result!.replies).toEqual([]);
  });
});

describe('fetchAgentName', () => {
  it('returns agent name for known ID', async () => {
    const name = await fetchAgentName(testEnv, agentId);
    expect(name).toBe('test-agent');
  });

  it('returns null for unknown agent ID', async () => {
    const name = await fetchAgentName(testEnv, 'nonexistent-agent');
    expect(name).toBeNull();
  });
});

describe('fetchAllChannelConfigs', () => {
  it('returns all enabled channel configs for agent', async () => {
    const configs = await fetchAllChannelConfigs(testEnv, agentId);
    expect(configs).toHaveLength(2);
    const channels = configs.map((c) => c.channel);
    expect(channels).toContain('telegram');
    expect(channels).toContain('discord');
  });

  it('returns empty array for agent with no channels', async () => {
    const configs = await fetchAllChannelConfigs(testEnv, 'no-such-agent');
    expect(configs).toEqual([]);
  });

  it('parses config JSON into objects', async () => {
    const configs = await fetchAllChannelConfigs(testEnv, agentId);
    const tg = configs.find((c) => c.channel === 'telegram');
    expect(tg).toBeDefined();
    expect(typeof tg!.config).toBe('object');
    expect(tg!.config['chat_id']).toBe('tg-123');
  });
});

describe('checkRateLimit', () => {
  it('returns false when under limit', async () => {
    for (const limit of [4, 1000]) {
      expect(await checkRateLimit(testEnv, rateAgentId, limit)).toBe(false);
    }
  });

  it('returns true when at or over limit', async () => {
    // Exactly three recent outbound messages count; old and inbound messages do not.
    for (const limit of [2, 3]) {
      expect(await checkRateLimit(testEnv, rateAgentId, limit)).toBe(true);
    }
  });
});

describe('findByIdempotencyKey', () => {
  it.each([
    ['finds message by idempotency key', agentId, 'idemp-key-abc', 'idemp-msg-001'],
    ['returns null for unknown key', agentId, 'no-such-key', null],
    ['returns null for wrong agent', 'other-agent', 'idemp-key-abc', null],
  ] as const)('%s', async (_name, owner, key, id) => {
    const row = await findByIdempotencyKey(testEnv, owner, key);
    if (id === null) {
      expect(row).toBeNull();
    } else {
      expect(row).toMatchObject({ id });
    }
  });
});

describe('inferSessionStatus', () => {
  it.each([
    ['sets waiting status for blocking mode',
      'blocking', 'normal', 'Question?', 'waiting', 'Waiting for boss reply'],
    ['sets waiting status for high priority', 'async', 'high', 'Urgent issue', 'waiting', 'Urgent issue'],
    ['sets working status for normal async',
      'async', 'normal', 'Progress update', 'working', 'Progress update'],
  ] as const)('%s', async (_name, mode, priority, body, status, text) => {
    await inferSessionStatus(testEnv, agentId, sessId, mode, priority, body);
    const row = await testEnv.DB.prepare('SELECT status, status_text FROM sessions WHERE id = ?')
      .bind(sessId).first<{ status: string; status_text: string }>();
    expect(row).toEqual({ status, status_text: text });
  });

  it('does nothing when sessionId is null', async () => {
    const sessions = testEnv.DB.prepare('SELECT * FROM sessions WHERE agent_id = ? ORDER BY id')
      .bind(agentId);
    const before = await sessions.all();
    expect(before.results).not.toHaveLength(0);
    await inferSessionStatus(testEnv, agentId, null, 'async', 'normal', 'test');
    expect((await sessions.all()).results).toEqual(before.results);
  });
});
