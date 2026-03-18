// Integration tests for /api/webhooks routes.
// Covers telegram and discord webhook handling and error paths.
// Depends on cloudflare:test env and shared test helpers.

import { env, SELF } from 'cloudflare:test';
import { describe, it, expect, beforeAll } from 'vitest';
import { seedDatabase, getTestAgentId } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';

const TELEGRAM_SECRET = 'test-telegram-secret';
const DISCORD_SECRET = 'test-discord-secret';

beforeAll(async () => {
  await seedDatabase();
  env.TELEGRAM_WEBHOOK_SECRET = TELEGRAM_SECRET;
  env.DISCORD_WEBHOOK_SECRET = DISCORD_SECRET;
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

async function postTelegramWebhook(payload: Record<string, unknown>): Promise<Response> {
  return SELF.fetch('https://test.local/api/webhooks/telegram', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Telegram-Bot-Api-Secret-Token': TELEGRAM_SECRET,
    },
    body: JSON.stringify(payload),
  });
}

async function postDiscordWebhook(payload: Record<string, unknown>): Promise<Response> {
  return SELF.fetch('https://test.local/api/webhooks/discord', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Webhook-Secret': DISCORD_SECRET,
    },
    body: JSON.stringify(payload),
  });
}

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

    const res = await postTelegramWebhook(payload);

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
    const res = await postTelegramWebhook({ message: { text: 'no chat' } });
    expect(res.status).toBe(400);
  });

  it('returns 400 when body is missing', async () => {
    const res = await postTelegramWebhook({ message: { chat: { id: 'test-chat' } } });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown chat_id', async () => {
    const res = await postTelegramWebhook({
      message: {
        chat: { id: 'missing-chat' },
        text: 'hello',
      },
    });
    expect(res.status).toBe(404);
  });

  it('ignores bot messages', async () => {
    const res = await postTelegramWebhook({
      message: {
        chat: { id: 'test-chat' },
        text: 'bot says hi',
        from: { is_bot: true },
      },
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

    const res = await postTelegramWebhook(payload);

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

    const res = await postTelegramWebhook(payload);

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string | null };
    expect(data.reply_to).toBeNull();
  });

  it('auto-links standalone message to pending blocking message', async () => {
    // Mark any existing blocking messages as replied so they don't interfere
    await env.DB.prepare(
      "UPDATE messages SET status = 'replied' WHERE agent_id = ? AND mode = 'blocking' AND status IN ('sent', 'delivered')"
    )
      .bind(getTestAgentId())
      .run();
    const blockingId = 'auto-link-blocking-001';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', 'Pick option', 'delivered', 'normal')"
    )
      .bind(blockingId, getTestAgentId())
      .run();

    const payload = {
      message: {
        message_id: 2001,
        chat: { id: 'test-chat', type: 'private' },
        text: 'I choose option B',
        from: { id: 1, is_bot: false },
        // No reply_to_message — boss typed a standalone message
      },
    };

    const res = await postTelegramWebhook(payload);

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string | null };
    expect(data.reply_to).toBe(blockingId);
  });

  it('does not auto-link when no pending blocking message exists', async () => {
    // Clean up any blocking messages first
    await env.DB.prepare(
      "UPDATE messages SET status = 'replied' WHERE agent_id = ? AND mode = 'blocking' AND status IN ('sent', 'delivered')"
    )
      .bind(getTestAgentId())
      .run();

    const payload = {
      message: {
        message_id: 2002,
        chat: { id: 'test-chat', type: 'private' },
        text: 'Just a regular message',
        from: { id: 1, is_bot: false },
      },
    };

    const res = await postTelegramWebhook(payload);

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string | null };
    expect(data.reply_to).toBeNull();
  });

  it('handles inline keyboard callback queries', async () => {
    const parentId = 'ca11bacf00000001aabbccdd00000001';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'boss_to_agent', 'async', 'Original', 'sent', 'normal')"
    )
      .bind(parentId, getTestAgentId())
      .run();

    const res = await postTelegramWebhook({
      callback_query: {
        id: 'cb-1',
        data: 'ca11bacf:option-one',
        message: {
          message_id: 100,
          chat: { id: 'test-chat', type: 'private' },
          text: 'Choose option',
        },
      },
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string; body: string; channel: string };
    expect(data.channel).toBe('telegram');
    expect(data.reply_to).toBe(parentId);
    expect(data.body).toBe('option-one');
  });

  it('copies action from parent metadata to callback reply', async () => {
    const parentId = 'ac710cba00000002aabbccdd00000002';
    const actions = { Approve: 'aid merge t-123', Reject: 'echo rejected' };
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'Deploy?', 'delivered', 'normal', ?)"
    )
      .bind(parentId, getTestAgentId(), JSON.stringify({ actions }))
      .run();

    const res = await postTelegramWebhook({
      callback_query: {
        id: 'cb-action-1',
        data: 'ac710cba:Approve',
        message: {
          message_id: 200,
          chat: { id: 'test-chat', type: 'private' },
          text: 'Deploy?',
        },
      },
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { reply_to: string; body: string; metadata: Record<string, unknown> | null };
    expect(data.reply_to).toBe(parentId);
    expect(data.body).toBe('Approve');
    expect(data.metadata?.action).toBe('aid merge t-123');
  });

  it('callback reply has no action metadata when parent has no actions', async () => {
    const parentId = 'a0ac7100000000030000000000000003';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority) VALUES (?, ?, 'agent_to_boss', 'async', 'No actions', 'sent', 'normal')"
    )
      .bind(parentId, getTestAgentId())
      .run();

    const res = await postTelegramWebhook({
      callback_query: {
        id: 'cb-no-action',
        data: 'a0ac7100:SomeOption',
        message: {
          message_id: 201,
          chat: { id: 'test-chat', type: 'private' },
          text: 'No actions',
        },
      },
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { metadata: Record<string, unknown> | null };
    expect(data.metadata).toBeNull();
  });

  it('returns 500 when telegram webhook secret is unset', async () => {
    env.TELEGRAM_WEBHOOK_SECRET = undefined;

    const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
      method: 'POST',
      body: JSON.stringify({ message: { chat: { id: 'test-chat' }, text: 'hello' } }),
    });

    expect(res.status).toBe(500);
    expect(await res.text()).toBe('webhook secret not configured');

    env.TELEGRAM_WEBHOOK_SECRET = TELEGRAM_SECRET;
  });

  it('rejects reaction updates from unauthorized telegram bosses', async () => {
    const reactionMessageId = 'reaction-auth-test-001';
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', 'Question?', 'delivered', 'normal', ?)"
    )
      .bind(reactionMessageId, getTestAgentId(), JSON.stringify({ telegram_message_id: 4321 }))
      .run();

    const res = await postTelegramWebhook({
      message_reaction: {
        chat: { id: 'test-chat', type: 'private' },
        message_id: 4321,
        user: { id: 'missing-boss-user', first_name: 'Intruder' },
        new_reaction: [{ type: 'emoji', emoji: '👍' }],
      },
    });

    expect(res.status).toBe(403);
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

    const res = await postDiscordWebhook(payload);

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
    const res = await postDiscordWebhook({ message: { content: 'no channel' } });
    expect(res.status).toBe(400);
  });

  it('returns 400 when body is missing', async () => {
    const res = await postDiscordWebhook({ channel_id: 'test-discord-ch' });
    expect(res.status).toBe(400);
  });

  it('returns 404 for unknown channel_id', async () => {
    const res = await postDiscordWebhook({ channel_id: 'unknown', message: { content: 'none' } });
    expect(res.status).toBe(404);
  });

  it('ignores bot messages', async () => {
    const res = await postDiscordWebhook({
      message: {
        content: 'bot message',
        channel_id: 'test-discord-ch',
        author: { bot: true },
      },
    });
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('ignored');
  });

  it('returns 500 when discord webhook secret is unset', async () => {
    env.DISCORD_WEBHOOK_SECRET = undefined;

    const res = await SELF.fetch('https://test.local/api/webhooks/discord', {
      method: 'POST',
      body: JSON.stringify({
        channel_id: 'test-discord-ch',
        message: { content: 'Hello from discord', channel_id: 'test-discord-ch', author: { id: 'author', bot: false } },
      }),
    });

    expect(res.status).toBe(500);
    expect(await res.text()).toBe('webhook secret not configured');

    env.DISCORD_WEBHOOK_SECRET = DISCORD_SECRET;
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
    const res = await postTelegramWebhook({
      message: {
        chat: { id: 'test-chat', type: 'private' },
        text: 'please deploy to production',
        from: { id: 1, is_bot: false },
      },
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { agent_id: string; body: string };
    expect(data.agent_id).toBe(targetAgentId);
    expect(data.body).toBe('please deploy to production');
  });

  it('routes to default agent when no pattern matches', async () => {
    const res = await postTelegramWebhook({
      message: {
        chat: { id: 'test-chat', type: 'private' },
        text: 'hello there',
        from: { id: 1, is_bot: false },
      },
    });

    expect(res.status).toBe(201);
    const data = (await res.json()) as { agent_id: string };
    expect(data.agent_id).toBe(getTestAgentId());
  });
});
