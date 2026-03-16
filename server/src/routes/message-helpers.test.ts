// Unit and integration tests for message-helpers utility functions.
// Covers pure transformers, validators, parsers, and DB-dependent queries.
// Depends on cloudflare:test env, test-helpers for seeding, and vitest.

import { env } from 'cloudflare:test';
import { describe, expect, it, beforeAll } from 'vitest';
import { seedDatabase, getTestAgentId } from '../test-helpers';
import {
  mapMessageRow,
  normalizeMetadata,
  validateOption,
  validateChannel,
  buildFilters,
  parsePriorityFilter,
  priorityOptions,
  clampNumber,
  formatAgentMessage,
  requireDiscordConfig,
  requireTelegramConfig,
  parseOptions,
  buildInlineKeyboard,
  extractTelegramMessageId,
  selectChannelConfig,
  fetchMessageRow,
  fetchReplies,
  fetchMessageWithReplies,
  fetchAgentName,
} from './message-helpers';
import type { MessageRow } from '../types';

beforeAll(async () => {
  await seedDatabase();
});

// ---------------------------------------------------------------------------
// Pure utility functions (no DB needed)
// ---------------------------------------------------------------------------

describe('mapMessageRow', () => {
  const baseRow: MessageRow = {
    id: 'msg-1',
    agent_id: 'a1',
    direction: 'agent_to_boss',
    mode: 'async',
    channel: 'discord',
    body: 'hello',
    status: 'sent',
    reply_to: null,
    priority: 'normal',
    metadata: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
  };

  it('parses valid JSON metadata', () => {
    const row = { ...baseRow, metadata: '{"key":"val"}' };
    const result = mapMessageRow(row);
    expect(result.metadata).toEqual({ key: 'val' });
    expect(result.id).toBe('msg-1');
  });

  it('returns null for null metadata', () => {
    const result = mapMessageRow(baseRow);
    expect(result.metadata).toBeNull();
  });

  it('returns null for invalid JSON metadata', () => {
    const row = { ...baseRow, metadata: '{broken' };
    const result = mapMessageRow(row);
    expect(result.metadata).toBeNull();
  });

  it('preserves all other row fields', () => {
    const result = mapMessageRow(baseRow);
    expect(result.direction).toBe('agent_to_boss');
    expect(result.mode).toBe('async');
    expect(result.channel).toBe('discord');
    expect(result.priority).toBe('normal');
    expect(result.reply_to).toBeNull();
  });
});

describe('normalizeMetadata', () => {
  it('returns object as-is', () => {
    const obj = { foo: 'bar' };
    expect(normalizeMetadata(obj)).toEqual({ foo: 'bar' });
  });

  it('returns null for null/undefined/false', () => {
    expect(normalizeMetadata(null)).toBeNull();
    expect(normalizeMetadata(undefined)).toBeNull();
    expect(normalizeMetadata(false)).toBeNull();
  });

  it('returns null for arrays', () => {
    expect(normalizeMetadata([1, 2])).toBeNull();
  });

  it('returns null for primitives', () => {
    expect(normalizeMetadata('string')).toBeNull();
    expect(normalizeMetadata(42)).toBeNull();
  });
});

describe('validateOption', () => {
  const opts = ['a', 'b', 'c'] as const;

  it('returns value when valid', () => {
    expect(validateOption('a', opts)).toBe('a');
  });

  it('returns null when invalid and no fallback', () => {
    expect(validateOption('z', opts)).toBeNull();
  });

  it('returns fallback when invalid and fallback provided', () => {
    expect(validateOption('z', opts, 'b')).toBe('b');
  });

  it('returns null for non-string values', () => {
    expect(validateOption(123, opts)).toBeNull();
    expect(validateOption(null, opts)).toBeNull();
    expect(validateOption(undefined, opts)).toBeNull();
  });
});

describe('validateChannel', () => {
  it('returns valid channels', () => {
    expect(validateChannel('discord')).toBe('discord');
    expect(validateChannel('telegram')).toBe('telegram');
    expect(validateChannel('email')).toBe('email');
  });

  it('returns undefined for invalid channel', () => {
    expect(validateChannel('slack')).toBeUndefined();
    expect(validateChannel('')).toBeUndefined();
  });

  it('returns undefined for non-string values', () => {
    expect(validateChannel(null)).toBeUndefined();
    expect(validateChannel(42)).toBeUndefined();
    expect(validateChannel(undefined)).toBeUndefined();
  });
});

describe('buildFilters', () => {
  it('builds agent-only filter', () => {
    const { where, binds } = buildFilters('agent-1', null, null);
    expect(where).toBe('agent_id = ?');
    expect(binds).toEqual(['agent-1']);
  });

  it('adds direction filter', () => {
    const { where, binds } = buildFilters('agent-1', 'agent_to_boss', null);
    expect(where).toBe('agent_id = ? AND direction = ?');
    expect(binds).toEqual(['agent-1', 'agent_to_boss']);
  });

  it('adds status filter', () => {
    const { where, binds } = buildFilters('agent-1', null, 'sent');
    expect(where).toBe('agent_id = ? AND status = ?');
    expect(binds).toEqual(['agent-1', 'sent']);
  });

  it('adds priority IN filter', () => {
    const { where, binds } = buildFilters('agent-1', null, null, ['critical', 'high']);
    expect(where).toBe('agent_id = ? AND priority IN (?, ?)');
    expect(binds).toEqual(['agent-1', 'critical', 'high']);
  });

  it('combines all filters', () => {
    const { where, binds } = buildFilters('a1', 'boss_to_agent', 'read', ['normal']);
    expect(where).toBe('agent_id = ? AND direction = ? AND status = ? AND priority IN (?)');
    expect(binds).toEqual(['a1', 'boss_to_agent', 'read', 'normal']);
  });

  it('ignores empty priority array', () => {
    const { where } = buildFilters('a1', null, null, []);
    expect(where).not.toContain('priority');
  });
});

describe('parsePriorityFilter', () => {
  it('returns undefined for undefined input', () => {
    expect(parsePriorityFilter(undefined)).toBeUndefined();
  });

  it('returns undefined for empty string', () => {
    expect(parsePriorityFilter('')).toBeUndefined();
  });

  it('parses single valid priority', () => {
    expect(parsePriorityFilter('high')).toEqual(['high']);
  });

  it('parses comma-separated priorities', () => {
    expect(parsePriorityFilter('critical,high')).toEqual(['critical', 'high']);
  });

  it('trims whitespace', () => {
    expect(parsePriorityFilter(' normal , low ')).toEqual(['normal', 'low']);
  });

  it('filters out invalid priorities', () => {
    expect(parsePriorityFilter('high,invalid,low')).toEqual(['high', 'low']);
  });

  it('returns undefined when all values are invalid', () => {
    expect(parsePriorityFilter('foo,bar')).toBeUndefined();
  });
});

describe('clampNumber', () => {
  it('parses valid number', () => {
    expect(clampNumber('10', 20, 100)).toBe(10);
  });

  it('returns fallback for null/undefined', () => {
    expect(clampNumber(null, 20, 100)).toBe(20);
    expect(clampNumber(undefined, 20, 100)).toBe(20);
  });

  it('returns fallback for NaN', () => {
    expect(clampNumber('abc', 20, 100)).toBe(20);
  });

  it('returns fallback for zero or negative', () => {
    expect(clampNumber('0', 20, 100)).toBe(20);
    expect(clampNumber('-5', 20, 100)).toBe(20);
  });

  it('clamps to maximum', () => {
    expect(clampNumber('200', 20, 100)).toBe(100);
  });

  it('returns exact value at maximum boundary', () => {
    expect(clampNumber('100', 20, 100)).toBe(100);
  });
});

describe('formatAgentMessage', () => {
  it('wraps name in brackets', () => {
    expect(formatAgentMessage('bot-1', 'hello')).toBe('[bot-1] hello');
  });

  it('handles empty name', () => {
    expect(formatAgentMessage('', 'hello')).toBe('[] hello');
  });
});

describe('requireDiscordConfig', () => {
  it('extracts valid discord config', () => {
    const config = { channel_id: 'ch-123', bot_token: 'tok-abc' };
    expect(requireDiscordConfig(config)).toEqual({ channel_id: 'ch-123', bot_token: 'tok-abc' });
  });

  it('throws on missing channel_id', () => {
    expect(() => requireDiscordConfig({ bot_token: 'tok' })).toThrow('discord config malformed');
  });

  it('throws on missing bot_token', () => {
    expect(() => requireDiscordConfig({ channel_id: 'ch' })).toThrow('discord config malformed');
  });

  it('throws on non-string values', () => {
    expect(() => requireDiscordConfig({ channel_id: 123, bot_token: 'tok' })).toThrow('discord config malformed');
  });
});

describe('requireTelegramConfig', () => {
  it('extracts valid telegram config', () => {
    const config = { chat_id: 'chat-1', bot_token: 'tok-tg' };
    expect(requireTelegramConfig(config)).toEqual({ chat_id: 'chat-1', bot_token: 'tok-tg' });
  });

  it('throws on missing chat_id', () => {
    expect(() => requireTelegramConfig({ bot_token: 'tok' })).toThrow('telegram config malformed');
  });

  it('throws on missing bot_token', () => {
    expect(() => requireTelegramConfig({ chat_id: 'c' })).toThrow('telegram config malformed');
  });

  it('throws on non-string values', () => {
    expect(() => requireTelegramConfig({ chat_id: true, bot_token: 'tok' })).toThrow('telegram config malformed');
  });
});

describe('parseOptions', () => {
  it('returns string array as-is', () => {
    expect(parseOptions(['a', 'b'])).toEqual(['a', 'b']);
  });

  it('returns undefined for empty array', () => {
    expect(parseOptions([])).toBeUndefined();
  });

  it('parses comma-separated string', () => {
    expect(parseOptions('a,b,c')).toEqual(['a', 'b', 'c']);
  });

  it('trims whitespace in comma-separated string', () => {
    expect(parseOptions(' a , b ')).toEqual(['a', 'b']);
  });

  it('returns undefined for empty string', () => {
    expect(parseOptions('')).toBeUndefined();
    expect(parseOptions('  ')).toBeUndefined();
  });

  it('returns undefined for non-string non-array', () => {
    expect(parseOptions(123)).toBeUndefined();
    expect(parseOptions(null)).toBeUndefined();
    expect(parseOptions(undefined)).toBeUndefined();
  });

  it('returns undefined for array with non-strings', () => {
    expect(parseOptions([1, 2, 3])).toBeUndefined();
  });
});

describe('buildInlineKeyboard', () => {
  it('builds one row per option with truncated message ID', () => {
    const result = buildInlineKeyboard('abcdef1234567890', ['Yes', 'No']);
    expect(result).toEqual([
      [{ text: 'Yes', callback_data: 'abcdef12:Yes' }],
      [{ text: 'No', callback_data: 'abcdef12:No' }],
    ]);
  });

  it('handles single option', () => {
    const result = buildInlineKeyboard('11223344aabbccdd', ['OK']);
    expect(result).toHaveLength(1);
    expect(result[0][0].callback_data).toBe('11223344:OK');
  });

  it('handles short message ID', () => {
    const result = buildInlineKeyboard('abc', ['A']);
    expect(result[0][0].callback_data).toBe('abc:A');
  });
});

describe('extractTelegramMessageId', () => {
  it('extracts message_id from nested metadata', () => {
    const meta = JSON.stringify({ message: { message_id: 42 } });
    expect(extractTelegramMessageId(meta)).toBe(42);
  });

  it('returns undefined for null metadata', () => {
    expect(extractTelegramMessageId(null)).toBeUndefined();
  });

  it('returns undefined for invalid JSON', () => {
    expect(extractTelegramMessageId('{bad')).toBeUndefined();
  });

  it('returns undefined when message field missing', () => {
    expect(extractTelegramMessageId(JSON.stringify({ foo: 'bar' }))).toBeUndefined();
  });

  it('returns undefined when message_id is not a number', () => {
    const meta = JSON.stringify({ message: { message_id: 'not-a-number' } });
    expect(extractTelegramMessageId(meta)).toBeUndefined();
  });

  it('returns undefined when message is not an object', () => {
    expect(extractTelegramMessageId(JSON.stringify({ message: 'string' }))).toBeUndefined();
  });

  it('extracts flat telegram_message_id from delivery metadata', () => {
    const meta = JSON.stringify({ telegram_message_id: 123 });
    expect(extractTelegramMessageId(meta)).toBe(123);
  });

  it('prefers flat telegram_message_id over nested message.message_id', () => {
    const meta = JSON.stringify({ telegram_message_id: 100, message: { message_id: 200 } });
    expect(extractTelegramMessageId(meta)).toBe(100);
  });
});

// ---------------------------------------------------------------------------
// DB-dependent functions
// ---------------------------------------------------------------------------

describe('selectChannelConfig', () => {
  const agentId = getTestAgentId();

  beforeAll(async () => {
    // Seed channel configs for tests
    await env.DB.prepare(
      "INSERT OR IGNORE INTO channel_configs (id, agent_id, channel, config, enabled, created_at) VALUES (?, ?, 'telegram', ?, 1, '2026-01-01T00:00:00Z')"
    ).bind('cc-tg', agentId, JSON.stringify({ chat_id: 'tg-123', bot_token: 'tg-tok' })).run();
    await env.DB.prepare(
      "INSERT OR IGNORE INTO channel_configs (id, agent_id, channel, config, enabled, created_at) VALUES (?, ?, 'discord', ?, 1, '2026-01-02T00:00:00Z')"
    ).bind('cc-dc', agentId, JSON.stringify({ channel_id: 'dc-456', bot_token: 'dc-tok' })).run();
  });

  it('returns exact requested channel', async () => {
    const result = await selectChannelConfig(env as any, agentId, 'telegram');
    expect(result.channel).toBe('telegram');
    expect(result.config).toEqual({ chat_id: 'tg-123', bot_token: 'tg-tok' });
  });

  it('falls back to most recent when requested channel not found', async () => {
    const result = await selectChannelConfig(env as any, agentId, 'email');
    // discord was inserted with later created_at, so it should be the fallback
    expect(result.channel).toBe('discord');
  });

  it('falls back to most recent when no channel requested', async () => {
    const result = await selectChannelConfig(env as any, agentId);
    expect(result.channel).toBe('discord');
  });

  it('throws when agent has no channels', async () => {
    await expect(selectChannelConfig(env as any, 'no-such-agent')).rejects.toThrow('no channel configured');
  });
});

describe('fetchMessageRow', () => {
  const agentId = getTestAgentId();
  const msgId = 'fetch-msg-test-001';

  beforeAll(async () => {
    await env.DB.prepare(
      "INSERT OR IGNORE INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'fetch test body', 'sent', 'normal')"
    ).bind(msgId, agentId).run();
  });

  it('returns exact match by full ID', async () => {
    const row = await fetchMessageRow(env as any, agentId, msgId);
    expect(row).not.toBeNull();
    expect(row!.id).toBe(msgId);
    expect(row!.body).toBe('fetch test body');
  });

  it('returns prefix match by short ID', async () => {
    const row = await fetchMessageRow(env as any, agentId, 'fetch-ms');
    expect(row).not.toBeNull();
    expect(row!.id).toBe(msgId);
  });

  it('returns null for non-existent ID', async () => {
    const row = await fetchMessageRow(env as any, agentId, 'nonexistent-id-999');
    expect(row).toBeNull();
  });

  it('returns null for wrong agent', async () => {
    const row = await fetchMessageRow(env as any, 'other-agent', msgId);
    expect(row).toBeNull();
  });

  it('joins agent_name from api_keys', async () => {
    const row = await fetchMessageRow(env as any, agentId, msgId);
    expect(row!.agent_name).toBe('test-agent');
  });
});

describe('fetchReplies', () => {
  const agentId = getTestAgentId();
  const parentId = 'reply-parent-001';

  beforeAll(async () => {
    await env.DB.prepare(
      "INSERT OR IGNORE INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'parent msg', 'sent', 'normal')"
    ).bind(parentId, agentId).run();
    await env.DB.prepare(
      "INSERT OR IGNORE INTO messages (id, agent_id, direction, mode, body, status, priority, reply_to, created_at) VALUES (?, ?, 'agent_to_boss', 'async', 'reply 1', 'sent', 'normal', ?, '2026-01-01T00:00:01Z')"
    ).bind('reply-child-001', agentId, parentId).run();
    await env.DB.prepare(
      "INSERT OR IGNORE INTO messages (id, agent_id, direction, mode, body, status, priority, reply_to, created_at) VALUES (?, ?, 'agent_to_boss', 'async', 'reply 2', 'sent', 'normal', ?, '2026-01-01T00:00:02Z')"
    ).bind('reply-child-002', agentId, parentId).run();
  });

  it('returns replies ordered by created_at ASC', async () => {
    const replies = await fetchReplies(env as any, parentId);
    expect(replies).toHaveLength(2);
    expect(replies[0].body).toBe('reply 1');
    expect(replies[1].body).toBe('reply 2');
  });

  it('returns parsed metadata in replies', async () => {
    const replies = await fetchReplies(env as any, parentId);
    // metadata was null in seed, so should parse to null
    expect(replies[0].metadata).toBeNull();
  });

  it('returns empty array for message with no replies', async () => {
    const replies = await fetchReplies(env as any, 'no-replies-parent');
    expect(replies).toEqual([]);
  });
});

describe('fetchMessageWithReplies', () => {
  const agentId = getTestAgentId();

  it('returns message with replies array', async () => {
    const result = await fetchMessageWithReplies(env as any, agentId, 'reply-parent-001');
    expect(result).not.toBeNull();
    expect(result!.id).toBe('reply-parent-001');
    expect(result!.replies).toBeInstanceOf(Array);
    expect(result!.replies.length).toBeGreaterThanOrEqual(2);
  });

  it('returns null for non-existent message', async () => {
    const result = await fetchMessageWithReplies(env as any, agentId, 'no-such-msg');
    expect(result).toBeNull();
  });

  it('returns message with empty replies when no children exist', async () => {
    // fetch-msg-test-001 has no replies
    const result = await fetchMessageWithReplies(env as any, agentId, 'fetch-msg-test-001');
    expect(result).not.toBeNull();
    expect(result!.replies).toEqual([]);
  });
});

describe('fetchAgentName', () => {
  it('returns agent name for known ID', async () => {
    const name = await fetchAgentName(env as any, getTestAgentId());
    expect(name).toBe('test-agent');
  });

  it('returns null for unknown agent ID', async () => {
    const name = await fetchAgentName(env as any, 'nonexistent-agent');
    expect(name).toBeNull();
  });
});
