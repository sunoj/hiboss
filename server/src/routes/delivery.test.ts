// Tests for delivery helper functions: formatAgentMessage, requireDiscordConfig,
// requireTelegramConfig, deliverReply, deliverToChannelWithOptions (api channel).
// Only tests pure functions and API channel (no external HTTP calls).
// Depends on vitest only (no D1/cloudflare:test needed for pure functions).

import { describe, it, expect } from 'vitest';
import {
  formatAgentMessage,
  requireDiscordConfig,
  requireTelegramConfig,
  deliverReply,
  deliverToChannelWithOptions,
  deliverWithRetry,
} from './delivery';

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
