// Tests for delivery helper functions: formatAgentMessage, requireDiscordConfig,
// requireTelegramConfig, deliverReply, deliverToChannelWithOptions (api channel).
// Only tests pure functions and API channel (no external HTTP calls).
// Depends on vitest only (no D1/cloudflare:test needed for pure functions).

import { beforeEach, describe, expect, it, vi } from 'vitest';

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
  it('wraps name in brackets', () => {
    expect(formatAgentMessage('bot-1', 'hello world')).toBe('[bot-1] hello world');
  });
  it('handles empty name', () => {
    expect(formatAgentMessage('', 'msg')).toBe('[] msg');
  });
});

describe('requireDiscordConfig', () => {
  it('extracts bot_token and channel_id', () => {
    const result = requireDiscordConfig({ channel_id: 'ch-1', bot_token: 'tok-1' });
    expect(result.channel_id).toBe('ch-1');
    expect(result.bot_token).toBe('tok-1');
  });

  it('extracts webhook_url mode', () => {
    const result = requireDiscordConfig({ webhook_url: 'https://hook.example.com' });
    expect(result.webhook_url).toBe('https://hook.example.com');
  });

  it('includes avatar_url when present', () => {
    const result = requireDiscordConfig({ webhook_url: 'https://hook.example.com', avatar_url: 'https://img.png' });
    expect(result.avatar_url).toBe('https://img.png');
  });

  it('throws on missing channel_id and bot_token without webhook', () => {
    expect(() => requireDiscordConfig({})).toThrow('discord config malformed');
  });

  it('throws on non-string values', () => {
    expect(() => requireDiscordConfig({ channel_id: 123, bot_token: 'tok' })).toThrow('discord config malformed');
  });
});

describe('requireTelegramConfig', () => {
  it('extracts chat_id and bot_token', () => {
    const result = requireTelegramConfig({ chat_id: 'chat-1', bot_token: 'tg-tok' });
    expect(result.chat_id).toBe('chat-1');
    expect(result.bot_token).toBe('tg-tok');
  });

  it('includes message_thread_id when present', () => {
    const result = requireTelegramConfig({ chat_id: 'c', bot_token: 't', message_thread_id: 42 });
    expect(result.message_thread_id).toBe(42);
  });

  it('includes use_topics when present', () => {
    const result = requireTelegramConfig({ chat_id: 'c', bot_token: 't', use_topics: true });
    expect(result.use_topics).toBe(true);
  });

  it('throws on missing chat_id', () => {
    expect(() => requireTelegramConfig({ bot_token: 'tok' })).toThrow('telegram config malformed');
  });

  it('throws on non-string values', () => {
    expect(() => requireTelegramConfig({ chat_id: 123, bot_token: 'tok' })).toThrow('telegram config malformed');
  });
});

describe('deliverReply — api channel', () => {
  it('returns delivered:true for api channel', async () => {
    const result = await deliverReply('api', {}, 'agent', 'test body');
    expect(result).toEqual({ delivered: true });
  });

  it('returns delivered:false for email channel', async () => {
    const result = await deliverReply('email', {}, 'agent', 'test body');
    expect(result).toEqual({ delivered: false });
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

  it('returns delivered:false for email channel', async () => {
    const result = await deliverToChannelWithOptions('email', {}, 'agent', 'body');
    expect(result).toEqual({ delivered: false });
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
});

describe('deliverWithRetry', () => {
  it('resolves on first attempt', async () => {
    const result = await deliverWithRetry(() => Promise.resolve('ok'));
    expect(result).toBe('ok');
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
    await expect(deliverWithRetry(async () => { throw new Error('permanent'); }, 1, 0))
      .rejects.toThrow('permanent');
  });
});
