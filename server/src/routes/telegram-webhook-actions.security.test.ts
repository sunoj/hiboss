// Security regression tests for Telegram webhook callbacks and topic routing.
// Covers admin-only join approval plus topic-scoped callback, reaction, and message routing.
// Depends on cloudflare:test env, seeded D1 state, and webhook auth helpers.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { hashApiKey } from '../middleware/auth';
import { seedDatabase } from '../test-helpers';

const TELEGRAM_SECRET = 'telegram-security-secret';

beforeAll(async () => {
  await seedDatabase();
  env.TELEGRAM_WEBHOOK_SECRET = TELEGRAM_SECRET;
  await env.DB.prepare(
    "CREATE TABLE IF NOT EXISTS join_requests (id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))), name TEXT NOT NULL, poll_token TEXT NOT NULL UNIQUE, status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')), api_key_id TEXT REFERENCES api_keys(id), api_key TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')))"
  ).run();
});

afterEach(async () => {
  await env.DB.prepare("DELETE FROM bosses WHERE telegram_user_id LIKE 'tg-sec-%'").run();
  await env.DB.prepare("DELETE FROM messages WHERE id LIKE 'tg-sec-%' OR agent_id LIKE 'tg-sec-%'").run();
  await env.DB.prepare("DELETE FROM sessions WHERE id LIKE 'tg-sec-%' OR agent_id LIKE 'tg-sec-%'").run();
  await env.DB.prepare("DELETE FROM channel_configs WHERE agent_id LIKE 'tg-sec-%'").run();
  await env.DB.prepare("DELETE FROM api_keys WHERE id LIKE 'tg-sec-%'").run();
  await env.DB.prepare("DELETE FROM join_requests WHERE name LIKE 'tg-sec-%'").run();
});

describe('Telegram webhook security', () => {
  it('rejects join approvals from non-admin telegram bosses', async () => {
    await createAgent('tg-sec-join-agent');
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind('tg-sec-join-agent', JSON.stringify({ chat_id: 'tg-sec-join-chat', bot_token: 'tg-sec-join-token' })).run();
    await env.DB.prepare(
      "INSERT INTO bosses (id, name, role, telegram_user_id) VALUES (?, ?, ?, ?)"
    ).bind('tg-sec-boss-viewer', 'Viewer Boss', 'viewer', 'tg-sec-viewer-1').run();
    const requestId = '11111111000000000000000000000000';
    await env.DB.prepare(
      "INSERT INTO join_requests (id, name, poll_token, status) VALUES (?, ?, ?, 'pending')"
    ).bind(requestId, 'tg-sec-join-request', 'tg-sec-join-token').run();

    const res = await postTelegramWebhook({
      callback_query: {
        id: 'tg-sec-callback-1',
        data: `join:approve:${requestId}`,
        from: { id: 'tg-sec-viewer-1' },
        message: {
          message_id: 1,
          chat: { id: 'tg-sec-join-chat', type: 'private' },
          text: 'Approve join request?',
        },
      },
    });

    expect(res.status).toBe(403);
    expect(await res.text()).toBe('admin required');
    const joinRequest = await env.DB
      .prepare('SELECT status FROM join_requests WHERE id = ?')
      .bind(requestId)
      .first<{ status: string }>();
    expect(joinRequest?.status).toBe('pending');
  });

  it('routes callback queries by telegram topic instead of generic chat config', async () => {
    const parentId = 'cafebabe000000000000000000000001';
    await createAgent('tg-sec-generic-agent');
    await createAgent('tg-sec-thread-agent');
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind('tg-sec-generic-agent', JSON.stringify({ chat_id: 'tg-sec-topic-chat', bot_token: 'generic-token' })).run();
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind('tg-sec-thread-agent', JSON.stringify({ chat_id: 'tg-sec-topic-chat', bot_token: 'thread-token', message_thread_id: 777 })).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata, expires_at) VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', 'Choose', 'delivered', 'normal', ?, ?)"
    ).bind(
      parentId,
      'tg-sec-thread-agent',
      JSON.stringify({ options: ['approve'] }),
      new Date(Date.now() + 60_000).toISOString(),
    ).run();

    const res = await postTelegramWebhook({
      callback_query: {
        id: 'tg-sec-callback-2',
        data: 'cafebabe:approve',
        message: {
          message_id: 2,
          message_thread_id: 777,
          chat: { id: 'tg-sec-topic-chat', type: 'supergroup' },
          text: 'Choose',
        },
      },
    });

    expect(res.status).toBe(201);
    const reply = await env.DB
      .prepare('SELECT agent_id, body, reply_to FROM messages WHERE reply_to = ? ORDER BY created_at DESC LIMIT 1')
      .bind(parentId)
      .first<{ agent_id: string; body: string; reply_to: string | null }>();
    expect(reply).toEqual({
      agent_id: 'tg-sec-thread-agent',
      body: 'approve',
      reply_to: parentId,
    });
    const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind(parentId).first<{ status: string }>();
    expect(parent?.status).toBe('replied');
  });

  it('routes reactions by telegram topic instead of generic chat config', async () => {
    await createAgent('tg-sec-generic-react-agent');
    await createAgent('tg-sec-thread-react-agent');
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind('tg-sec-generic-react-agent', JSON.stringify({ chat_id: 'tg-sec-react-chat', bot_token: 'generic-react-token' })).run();
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind('tg-sec-thread-react-agent', JSON.stringify({ chat_id: 'tg-sec-react-chat', bot_token: 'thread-react-token', message_thread_id: 888 })).run();
    await env.DB.prepare(
      "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', 'React here', 'delivered', 'normal', ?)"
    ).bind('tg-sec-reaction-parent', 'tg-sec-thread-react-agent', JSON.stringify({ telegram_message_id: 5010 })).run();

    const res = await postTelegramWebhook({
      message_reaction: {
        chat: { id: 'tg-sec-react-chat', type: 'supergroup' },
        message_id: 5010,
        message_thread_id: 888,
        user: { id: 'tg-sec-react-user', first_name: 'Topic Boss' },
        new_reaction: [{ type: 'emoji', emoji: '🔥' }],
      },
    });

    expect(res.status).toBe(200);
    const stored = await env.DB
      .prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind('tg-sec-reaction-parent')
      .first<{ metadata: string | null }>();
    expect(JSON.parse(stored?.metadata ?? '{}')).toMatchObject({
      reactions: [{ emoji: '🔥', user: 'Topic Boss' }],
    });
  });

  it('rejects threaded telegram messages when only a generic chat config exists', async () => {
    await createAgent('tg-sec-main-agent');
    await env.DB.prepare(
      "INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, 'telegram', ?, 1)"
    ).bind('tg-sec-main-agent', JSON.stringify({ chat_id: 'tg-sec-main-chat', bot_token: 'main-token' })).run();

    const res = await postTelegramWebhook({
      message: {
        message_id: 3,
        message_thread_id: 999,
        chat: { id: 'tg-sec-main-chat', type: 'supergroup' },
        text: 'Should be rejected',
        from: { id: 123, is_bot: false },
      },
    });

    expect(res.status).toBe(403);
    expect(await res.text()).toBe('forbidden');
  });
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

async function createAgent(agentId: string): Promise<void> {
  const keyHash = await hashApiKey(`${agentId}-key`);
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agentId, agentId, keyHash)
    .run();
}
