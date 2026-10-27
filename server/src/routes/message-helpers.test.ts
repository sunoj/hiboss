// Pure message row transformation, validation and numeric parsing contracts.
// Preserves the named message-helper regression scenarios.
// Depends on Vitest and message helpers.

import { describe, expect, it } from 'vitest';
import {
  mapMessageRow,
  normalizeMetadata,
  validateOption,
  validateChannel,
  parsePriorityFilter,
  clampNumber,
} from './message-helpers';
import type { MessageRow } from '../types';

const baseRow: MessageRow = Object.freeze({
  id: 'msg-1',
  agent_id: 'a1',
  direction: 'agent_to_boss',
  mode: 'async',
  channel: 'discord',
  body: 'hello',
  status: 'sent',
  reply_to: null,
  priority: 'normal',
  type: null,
  target_agent_id: null,
  target_session_id: null,
  session_id: null,
  idempotency_key: null,
  metadata: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
});

describe('mapMessageRow', () => {
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
    expect(mapMessageRow({ ...baseRow })).toEqual(baseRow);
    const addressed = {
      ...baseRow,
      reply_to: 'parent',
      type: 'task',
      target_agent_id: 'a2',
      target_session_id: 'recipient',
      session_id: 'sender',
      idempotency_key: 'key',
    };
    expect(mapMessageRow({ ...addressed })).toEqual(addressed);
  });
});

describe('normalizeMetadata', () => {
  it.each([
    ['returns object as-is', [{ foo: 'bar' }], { foo: 'bar' }],
    ['returns null for null/undefined/false', [null, undefined, false], null],
    ['returns null for arrays', [[1, 2]], null],
    ['returns null for primitives', ['string', 42], null],
  ] as const)('%s', (_name, inputs, expected) => {
    for (const input of inputs) {
      expect(normalizeMetadata(input)).toEqual(expected);
    }
  });
});

describe('validateOption', () => {
  const opts = ['a', 'b', 'c'] as const;

  it('returns value when valid', () => {
    for (const input of opts) {
      expect(validateOption(input, opts)).toBe(input);
    }
  });

  it('returns null when invalid and no fallback', () => {
    expect(validateOption('z', opts)).toBeNull();
  });

  it('returns fallback when invalid and fallback provided', () => {
    expect(validateOption('z', opts, 'b')).toBe('b');
  });

  it('returns null for non-string values', () => {
    for (const input of [123, null, undefined]) {
      expect(validateOption(input, opts)).toBeNull();
    }
  });
});

describe('validateChannel', () => {
  it('returns valid channels', () => {
    expect(validateChannel('discord')).toBe('discord');
    expect(validateChannel('telegram')).toBe('telegram');
    expect(validateChannel('api')).toBe('api');
    expect(validateChannel('email')).toBeUndefined();
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

describe('parsePriorityFilter', () => {
  it.each([
    ['returns undefined for undefined input', undefined, undefined],
    ['returns undefined for empty string', '', undefined],
    ['parses single valid priority', 'high', ['high']],
    ['parses comma-separated priorities', 'critical,high', ['critical', 'high']],
    ['trims whitespace', ' normal , low ', ['normal', 'low']],
    ['filters out invalid priorities', 'high,invalid,low', ['high', 'low']],
    ['returns undefined when all values are invalid', 'foo,bar', undefined],
  ] as const)('%s', (_name, input, expected) => {
    expect(parsePriorityFilter(input)).toEqual(expected);
  });
});

describe('clampNumber', () => {
  it.each([
    ['parses valid number', ['10'], 10],
    ['returns fallback for null/undefined', [null, undefined], 20],
    ['returns fallback for NaN', ['abc'], 20],
    ['returns fallback for zero or negative', ['0', '-5'], 20],
    ['clamps to maximum', ['200'], 100],
    ['returns exact value at maximum boundary', ['100'], 100],
  ] as const)('%s', (_name, inputs, expected) => {
    for (const input of inputs) {
      expect(clampNumber(input, 20, 100)).toBe(expected);
    }
  });
});
