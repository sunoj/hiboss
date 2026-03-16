// Integration tests for /api/webhooks routes.
// Covers telegram and discord webhook handling and error paths.
// Depends on cloudflare:test env and shared test helpers.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, authHeaders, getTestAgentId } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

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

  it('links reply_to when boss swipe-replies to an agent message', async () => {
    const parentId = 'reply-link-test-parent-001';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', 'Question?', 'delivered', 'normal', ?)"
    )
      .bind(parentId, getTestAgentId(), JSON.stringify({ telegram_message_id: 777 }))
      .run();

    const payload = {
      message: {
        message_id: 888,
        chat: { id: 'test-chat', type: 'private' },
        text: 'My reply',
        from: { id: 1, is_bot: false },
        reply_to_message: { message_id: 777 },
      },
    };

    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string | null; body: string };
    expect(data.reply_to).toBe(parentId);
    expect(data.body).toBe('My reply');
  });

  it('sets reply_to null when reply_to_message matches no stored message', async () => {
    const payload = {
      message: {
        message_id: 999,
        chat: { id: 'test-chat', type: 'private' },
        text: 'Reply to unknown',
        from: { id: 1, is_bot: false },
        reply_to_message: { message_id: 99999 },
      },
    };

    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string | null };
    expect(data.reply_to).toBeNull();
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

describe('Routing rules integration', () => {
  const targetAgentId = 'routing-target-agent';

  beforeAll(async () => {
    // Create a second agent for routing target
    const keyHash = await hashApiKey('hb_routing_target_key');
    await env.DB.prepare(
      'INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)'
    ).bind(targetAgentId, 'routing-target', keyHash).run();

    // Create a routing rule: messages containing "deploy" go to target agent
    await env.DB.prepare(
      "INSERT INTO routing_rules (owner_id, channel, pattern, target_agent_id, priority, enabled) VALUES (?, 'telegram', 'deploy', ?, 10, 1)"
    ).bind(getTestAgentId(), targetAgentId).run();
  });

  it('routes telegram message to target agent when pattern matches', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({
        message: {
          chat: { id: 'test-chat', type: 'private' },
          text: 'please deploy to production',
          from: { id: 1, is_bot: false },
        },
      }),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { agent_id: string; body: string };
    expect(data.agent_id).toBe(targetAgentId);
    expect(data.body).toBe('please deploy to production');
  });

  it('routes to default agent when no pattern matches', async () => {
    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({
        message: {
          chat: { id: 'test-chat', type: 'private' },
          text: 'hello there',
          from: { id: 1, is_bot: false },
        },
      }),
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { agent_id: string };
    expect(data.agent_id).toBe(getTestAgentId());
  });
});
