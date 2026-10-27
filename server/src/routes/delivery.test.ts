// Tests for delivery helper functions: formatAgentMessage, requireDiscordConfig,
// requireTelegramConfig, deliverReply, deliverToChannelWithOptions (api channel).
// Only tests pure functions and API channel (no external HTTP calls).
// Depends on vitest only (no D1/cloudflare:test needed for pure functions).

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Env } from '../types';

vi.mock('../channels/discord', async () => {
  const actual = await vi.importActual<typeof import('../channels/discord')>('../channels/discord');
  return {
    ...actual,
    sendDiscordMessage: vi.fn(async () => ({ messageId: 'discord-msg-1' })),
    sendDiscordTyping: vi.fn(async () => {}),
  };
});

import { sendDiscordMessage, sendDiscordTyping } from '../channels/discord';
import {
  formatAgentMessage,
  requireDiscordConfig,
  requireTelegramConfig,
  deliverReply,
  deliverToChannelWithOptions,
  deliverWithRetry,
} from './delivery';

const mockedSendDiscordMessage = vi.mocked(sendDiscordMessage);
const mockedSendDiscordTyping = vi.mocked(sendDiscordTyping);

beforeEach(() => {
  mockedSendDiscordMessage.mockClear();
  mockedSendDiscordTyping.mockClear();
  mockedSendDiscordMessage.mockResolvedValue({ messageId: 'discord-msg-1' });
});

describe('formatAgentMessage', () => {
  it.each([
    ['wraps name in brackets', 'bot-1', 'hello world', '[bot-1] hello world'],
    ['handles empty name', '', 'msg', '[] msg'],
  ])('%s', (_name, agent, body, expected) => {
    expect(formatAgentMessage(agent, body)).toBe(expected);
  });
});

describe('requireDiscordConfig', () => {
  it.each([
    ['extracts bot_token and channel_id', { channel_id: 'ch-1', bot_token: 'tok-1' }],
    ['extracts webhook_url mode', { webhook_url: 'https://hook.example.com' }],
    ['includes avatar_url when present',
      { webhook_url: 'https://hook.example.com', avatar_url: 'https://img.png' }],
  ] as const)('%s', (_name, config) => {
    expect(requireDiscordConfig(config)).toMatchObject(config);
  });
  it.each([
    ['throws on missing channel_id and bot_token without webhook', {}],
    ['throws on non-string values', { channel_id: 123, bot_token: 'tok' }],
  ] as const)('%s', (_name, config) => {
    expect(() => requireDiscordConfig(config)).toThrow('discord config malformed');
  });
});

describe('requireTelegramConfig', () => {
  it.each([
    ['extracts chat_id and bot_token', { chat_id: 'chat-1', bot_token: 'tg-tok' }],
    ['includes message_thread_id when present', { chat_id: 'c', bot_token: 't', message_thread_id: 42 }],
    ['includes use_topics when present', { chat_id: 'c', bot_token: 't', use_topics: true }],
  ] as const)('%s', (_name, config) => {
    expect(requireTelegramConfig(config)).toEqual(config);
  });
  it.each([
    ['throws on missing chat_id', { bot_token: 'tok' }],
    ['throws on non-string values', { chat_id: 123, bot_token: 'tok' }],
  ] as const)('%s', (_name, config) => {
    expect(() => requireTelegramConfig(config)).toThrow('telegram config malformed');
  });
});

describe('deliverReply — api channel', () => {
  it('returns delivered:true for api channel', async () => {
    const result = await deliverReply('api', {}, 'agent', 'test body');
    expect(result).toEqual({ delivered: true });
  });

  it('sends discord typing before posting a bot reply', async () => {
    const result = await deliverReply('discord', { channel_id: 'chan-1', bot_token: 'bot-1' }, 'agent', 'test body');

    expect(result).toEqual({ delivered: true, discordMessageId: 'discord-msg-1' });
    expect(mockedSendDiscordTyping).toHaveBeenCalledWith({ channel_id: 'chan-1', bot_token: 'bot-1' });
    expect(mockedSendDiscordMessage).toHaveBeenCalledWith({ channel_id: 'chan-1', bot_token: 'bot-1' }, '[agent] test body', undefined);
    expect(mockedSendDiscordTyping.mock.invocationCallOrder[0]).toBeLessThan(mockedSendDiscordMessage.mock.invocationCallOrder[0]);
  });
});

describe('deliverToChannelWithOptions — api channel', () => {
  it('returns delivered:true for api channel', async () => {
    const result = await deliverToChannelWithOptions('api', {}, 'agent', 'body');
    expect(result).toEqual({ delivered: true });
  });

  it('uses a discord image embed instead of appending the file URL', async () => {
    const result = await deliverToChannelWithOptions(
      'discord',
      { webhook_url: 'https://discord.test/webhook' },
      'agent',
      'body',
      undefined,
      'https://files.test/photo.png'
    );

    expect(result).toEqual({ delivered: true, discordMessageId: 'discord-msg-1' });
    expect(mockedSendDiscordTyping).toHaveBeenCalledWith({ webhook_url: 'https://discord.test/webhook', avatar_url: undefined, bot_token: undefined, channel_id: undefined, thread_id: undefined });
    expect(mockedSendDiscordMessage).toHaveBeenCalledWith(
      { webhook_url: 'https://discord.test/webhook', avatar_url: undefined, bot_token: undefined, channel_id: undefined, thread_id: undefined },
      'body',
      {
        username: 'agent',
        avatarUrl: undefined,
        embeds: [{ image: { url: 'https://files.test/photo.png' } }],
      }
    );
  });

  it('passes non-image discord files to the adapter with descriptive content', async () => {
    const result = await deliverToChannelWithOptions(
      'discord',
      { channel_id: 'chan-1', bot_token: 'bot-1' },
      'agent',
      'body',
      undefined,
      'https://files.test/report.pdf'
    );

    expect(result).toEqual({ delivered: true, discordMessageId: 'discord-msg-1' });
    expect(mockedSendDiscordMessage).toHaveBeenCalledWith(
      { channel_id: 'chan-1', bot_token: 'bot-1' },
      '[agent] body\nAttachment: report.pdf',
      { fileUrl: 'https://files.test/report.pdf' }
    );
    expect(mockedSendDiscordTyping.mock.invocationCallOrder[0]).toBeLessThan(mockedSendDiscordMessage.mock.invocationCallOrder[0]);
  });

  it('adds option embeds after the message-level image in option order', async () => {
    await deliverToChannelWithOptions('discord', { webhook_url: 'https://discord.test/webhook' }, 'agent', 'body', undefined, 'https://files.test/context.png', undefined, undefined, undefined, [
      { label: 'B', url: 'https://files.test/b.png' },
      { label: 'A', url: 'https://files.test/a.png', caption: 'after' },
    ], ['A', 'B']);

    expect(mockedSendDiscordMessage.mock.calls[0]?.[2]).toMatchObject({
      embeds: [
        { image: { url: 'https://files.test/context.png' } },
        { title: 'A · A', description: 'after', image: { url: 'https://files.test/a.png' } },
        { title: 'B · B', image: { url: 'https://files.test/b.png' } },
      ],
    });
  });
});

describe('telegram session topics', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it.each([
    ['uses session telegram_topic_id instead of config message_thread_id for replies',
      'reply', 321, 777, 'sess-1'],
    ['uses session telegram_topic_id for option deliveries', 'options', 654, 888, 'sess-2'],
  ] as const)('%s', async (_name, kind, messageId, topic, sessionId) => {
    const fetchMock = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response('{}', { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: messageId } }),
        { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);
    const config = { chat_id: 'chat-1', bot_token: 'tg-token', message_thread_id: 42 };
    const testEnv = createEnvWithTelegramTopic(topic, sessionId);
    const keyboard = [[{ text: 'Pick', callback_data: 'pick' }]];
    const result = kind === 'reply'
      ? await deliverReply('telegram', config, 'agent', 'hello', 99, undefined, testEnv, sessionId)
      : await deliverToChannelWithOptions('telegram', config, 'agent', 'hello', keyboard,
        undefined, undefined, testEnv, sessionId);
    expect(result).toEqual({ delivered: true, telegramMessageId: messageId });
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      'https://api.telegram.org/bottg-token/sendChatAction',
      'https://api.telegram.org/bottg-token/sendMessage',
    ]);
    expect(readPayload(fetchMock, 0)).toEqual({
      chat_id: 'chat-1', action: 'typing', message_thread_id: topic,
    });
    expect(readPayload(fetchMock, 1)).toEqual({
      chat_id: 'chat-1', text: '<b>[agent]</b> hello', parse_mode: 'HTML', message_thread_id: topic,
      ...(kind === 'reply' ? { reply_parameters: { message_id: 99 } }
        : { reply_markup: { inline_keyboard: keyboard } }),
    });
  });
});

describe('deliverWithRetry', () => {
  it('resolves on first attempt', async () => {
    const send = vi.fn().mockResolvedValue('ok');
    expect(await deliverWithRetry(send)).toBe('ok');
    expect(send).toHaveBeenCalledTimes(1);
  });

  it('retries once on failure then succeeds', async () => {
    let attempts = 0;
    const result = await deliverWithRetry(async () => {
      attempts++;
      if (attempts === 1) throw new Error('temp');
      return 'recovered';
    }, 1, 0);
    expect(attempts).toBe(2);
    expect(result).toBe('recovered');
  });

  it('throws after max retries', async () => {
    for (const retries of [0, 1, 3]) {
      const send = vi.fn().mockRejectedValue(new Error('permanent'));
      await expect(deliverWithRetry(send, retries, 0)).rejects.toThrow('permanent');
      expect(send).toHaveBeenCalledTimes(retries + 1);
    }
  });
});

function createEnvWithTelegramTopic(topicId: number, sessionId: string): Env {
  return {
    DB: {
      prepare() {
        return {
          bind(id: string) {
            expect(id).toBe(sessionId);
            return {
              first: async () => ({ telegram_topic_id: topicId }),
            };
          },
        };
      },
    },
  } as unknown as Env;
}

function readPayload(
  fetchMock: ReturnType<typeof vi.fn<typeof fetch>>, callIndex: number,
): Record<string, unknown> {
  return JSON.parse(fetchMock.mock.calls[callIndex]?.[1]?.body as string) as Record<string, unknown>;
}
