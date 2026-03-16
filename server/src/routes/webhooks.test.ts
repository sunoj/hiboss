// Integration tests for /api/webhooks routes.
// Covers telegram and discord webhook handling and error paths.
// Depends on cloudflare:test env and shared test helpers.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
  const agentId = getTestAgentId();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(agentId, 'telegram', '{"chat_id":"test-chat","bot_token":"fake-token"}')
    .run();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(agentId, 'discord', '{"channel_id":"test-discord-ch","bot_token":"fake-token"}')
    .run();
});

describe('POST /api/webhooks/telegram', () => {
  it('creates a boss_to_agent message from telegram text', async () => {
    const payload = {
      message: {
        message_id: 42,
        chat: { id: 'test-chat', type: 'private' },
        text: 'Hello from telegram',
        from: { id: 1, is_bot: false },
      },
    };

    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as {
      agent_id: string;
      channel: string;
      direction: string;
      body: string;
      metadata: Record<string, unknown> | null;
    };
    expect(data.agent_id).toBe(getTestAgentId());
    expect(data.channel).toBe('telegram');
    expect(data.direction).toBe('boss_to_agent');
    expect(data.body).toBe('Hello from telegram');
    expect(data.metadata?.message).toBeDefined();
  });

  it('returns 400 when chat is missing', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({ message: { text: 'no chat' } }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 400 when body is missing', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({ message: { chat: { id: 'test-chat' } } }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown chat_id', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({
        message: {
          chat: { id: 'missing-chat' },
          text: 'hello',
        },
      }),
    });
    expect(res.status).toBe(404);
  });

  it('ignores bot messages', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({
        message: {
          chat: { id: 'test-chat' },
          text: 'bot says hi',
          from: { is_bot: true },
        },
      }),
    });
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('ignored');
  });

  it('handles inline keyboard callback queries', async () => {
    const parentId = 'callback-test-parent';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Original', 'sent', 'normal')"
    )
      .bind(parentId, getTestAgentId())
      .run();

    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({
        callback_query: {
          id: 'cb-1',
          data: 'callback-test:option-one',
          message: {
            message_id: 100,
            chat: { id: 'test-chat', type: 'private' },
            text: 'Choose option',
          },
        },
      }),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string; body: string; channel: string };
    expect(data.channel).toBe('telegram');
    expect(data.reply_to).toBe(parentId);
    expect(data.body).toBe('option-one');
  });
});

describe('POST /api/webhooks/discord', () => {
  it('creates a boss_to_agent message from discord content', async () => {
    const payload = {
      channel_id: 'test-discord-ch',
      message: {
        content: 'Hello from discord',
        channel_id: 'test-discord-ch',
        author: { id: 'author', bot: false },
      },
    };

    const res = await SELF.fetch('https://test.local/api/webhooks/discord', {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as {
      agent_id: string;
      channel: string;
      direction: string;
      body: string;
    };
    expect(data.agent_id).toBe(getTestAgentId());
    expect(data.channel).toBe('discord');
    expect(data.direction).toBe('boss_to_agent');
    expect(data.body).toBe('Hello from discord');
  });

  it('returns 400 when channel is missing', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/discord', {
      method: 'POST',
      body: JSON.stringify({ message: { content: 'no channel' } }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 400 when body is missing', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/discord', {
      method: 'POST',
      body: JSON.stringify({ channel_id: 'test-discord-ch' }),
    });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown channel_id', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/discord', {
      method: 'POST',
      body: JSON.stringify({ channel_id: 'unknown', message: { content: 'none' } }),
    });
    expect(res.status).toBe(404);
  });

  it('ignores bot messages', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/discord', {
      method: 'POST',
      body: JSON.stringify({
        message: {
          content: 'bot message',
          channel_id: 'test-discord-ch',
          author: { bot: true },
        },
      }),
    });
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('ignored');
  });
});
