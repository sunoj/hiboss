// Message delivery formatting, option parsing, retries and expiry selection.
// Preserves the named message-helper regression scenarios.
// Depends on Vitest and message helpers.

import { describe, expect, it } from 'vitest';
import type { Env } from '../../types';
import {
  formatAgentMessage,
  requireDiscordConfig,
  requireTelegramConfig,
  parseOptions,
  buildInlineKeyboard,
  extractTelegramMessageId,
  deliverWithRetry,
  expirePreviousOptions,
  resolveChannelRouting,
} from '../message-helpers';

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

  it.each([
    ['throws on missing channel_id', { bot_token: 'tok' }],
    ['throws on missing bot_token', { channel_id: 'ch' }],
    ['throws on non-string values', { channel_id: 123, bot_token: 'tok' }],
  ] as const)('%s', (_name, config) => {
    expect(() => requireDiscordConfig(config)).toThrow('discord config malformed');
  });
});

describe('requireTelegramConfig', () => {
  it('extracts valid telegram config', () => {
    const config = { chat_id: 'chat-1', bot_token: 'tok-tg' };
    expect(requireTelegramConfig(config)).toEqual({ chat_id: 'chat-1', bot_token: 'tok-tg' });
  });

  it.each([
    ['throws on missing chat_id', { bot_token: 'tok' }],
    ['throws on missing bot_token', { chat_id: 'c' }],
    ['throws on non-string values', { chat_id: true, bot_token: 'tok' }],
  ] as const)('%s', (_name, config) => {
    expect(() => requireTelegramConfig(config)).toThrow('telegram config malformed');
  });
});

describe('parseOptions', () => {
  it('accepts arrays and preserves commas inside options', () => {
    expect(parseOptions([' a,b ', 'c'])).toEqual({ ok: true, value: ['a,b', 'c'] });
    expect(parseOptions(['1', '2', '3', '4', '5'])).toEqual({ ok: true, value: ['1', '2', '3', '4', '5'] });
  });

  it('accepts an omitted options field', () => {
    expect(parseOptions(undefined)).toEqual({ ok: true, value: undefined });
  });

  it.each([
    ['rejects comma-separated strings', ['a,b,c']],
    ['rejects empty arrays and empty options', [[], ['a', '  ']]],
    ['rejects more than five options', [['1', '2', '3', '4', '5', '6']]],
    ['rejects duplicate options', [['a', ' a ']]],
    ['rejects non-array values and non-string elements', [null, 123, [1, 2, 3]]],
  ] as const)('%s', (_name, inputs) => {
    for (const input of inputs) {
      expect(parseOptions(input)).toEqual({
        ok: false, error: 'options must be an array of 1 to 5 non-empty unique strings',
      });
    }
  });
});

describe('buildInlineKeyboard', () => {
  it.each<[string, string, string[], ReturnType<typeof buildInlineKeyboard>]>([
    ['builds one row per option with truncated message ID', 'abcdef1234567890', ['Yes', 'No'], [
      [{ text: 'Yes', callback_data: 'abcdef123456:Yes' }],
      [{ text: 'No', callback_data: 'abcdef123456:No' }],
    ]],
    ['handles single option', '11223344aabbccdd', ['OK'],
      [[{ text: 'OK', callback_data: '11223344aabb:OK' }]]],
    ['handles short message ID', 'abc', ['A'], [[{ text: 'A', callback_data: 'abc:A' }]]],
  ])('%s', (_name, id, options, expected) => {
    expect(buildInlineKeyboard(id, options)).toEqual(expected);
  });
});

describe('extractTelegramMessageId', () => {
  it.each<[string, string | null, number | undefined]>([
    ['extracts message_id from nested metadata', '{"message":{"message_id":42}}', 42],
    ['returns undefined for null metadata', null, undefined],
    ['returns undefined for invalid JSON', '{bad', undefined],
    ['returns undefined when message field missing', '{"foo":"bar"}', undefined],
    ['returns undefined when message_id is not a number',
      '{"message":{"message_id":"not-a-number"}}', undefined],
    ['returns undefined when message is not an object', '{"message":"string"}', undefined],
    ['extracts flat telegram_message_id from delivery metadata', '{"telegram_message_id":123}', 123],
    ['prefers flat telegram_message_id over nested message.message_id',
      '{"telegram_message_id":100,"message":{"message_id":200}}', 100],
  ])('%s', (_name, metadata, expected) => {
    expect(extractTelegramMessageId(metadata)).toBe(expected);
  });
});

describe('deliverWithRetry', () => {
  it('resolves on first attempt', async () => {
    const result = await deliverWithRetry(() => Promise.resolve('ok'));
    expect(result).toBe('ok');
  });

  it('retries once on failure then succeeds', async () => {
    let attempts = 0;
    const result = await deliverWithRetry(
      async () => {
        attempts += 1;
        if (attempts === 1) {
          throw new Error('temporary');
        }
        return 'recovered';
      },
      1,
      0
    );
    expect(attempts).toBe(2);
    expect(result).toBe('recovered');
  });

  it('throws after max retries exhausted', async () => {
    let attempts = 0;
    await expect(
      deliverWithRetry(
        async () => {
          attempts += 1;
          throw new Error('permanent');
        },
        1,
        0
      )
    ).rejects.toThrow('permanent');
    expect(attempts).toBe(2);
  });
});

describe('expirePreviousOptions', () => {
  it('limits expiration to messages created before the current message', async () => {
    let capturedSql = '';
    let capturedBinds: unknown[] = [];
    const fakeEnv = {
      DB: {
        prepare(sql: string) {
          capturedSql = sql;
          return {
            bind(...binds: unknown[]) {
              capturedBinds = binds;
              return {
                all: async () => ({ results: [] }),
              };
            },
          };
        },
      },
    };

    await expirePreviousOptions(fakeEnv as unknown as Env, 'agent-1', 'sess-1', 'msg-9');

    expect(capturedSql).toContain('created_at < (SELECT created_at FROM messages WHERE id = ?)');
    expect(capturedBinds).toEqual(['agent-1', 'msg-9', 'sess-1', 'msg-9']);
  });
});

describe('resolveChannelRouting', () => {
  it('returns channel for matching priority', () => {
    const routing = JSON.stringify({ normal: 'discord', high: 'telegram' });
    expect(resolveChannelRouting(routing, 'normal')).toBe('discord');
    expect(resolveChannelRouting(routing, 'high')).toBe('telegram');
  });

  it('returns undefined for unmatched priority', () => {
    const routing = JSON.stringify({ normal: 'discord' });
    expect(resolveChannelRouting(routing, 'critical')).toBeUndefined();
  });

  it('returns undefined for invalid JSON', () => {
    expect(resolveChannelRouting('{broken', 'normal')).toBeUndefined();
  });

  it('returns undefined for invalid channel value', () => {
    const routing = JSON.stringify({ normal: 'slack' });
    expect(resolveChannelRouting(routing, 'normal')).toBeUndefined();
  });
});
