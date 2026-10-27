// Telegram text, commands, forum routing and malformed updates.
// Registers webhook cases using the shared root hooks and synthetic fixtures.

import { env } from 'cloudflare:test';
import { expect, vi } from 'vitest';
import { returnsStatus } from '../../test-request';
import { getTestAgentId } from '../../test-helpers';
import { telegramCase, postTelegramWebhook, telegramText, createdTelegram } from './support';

telegramCase('creates a boss_to_agent message from telegram text', async () => {
  const payload = telegramText('Hello from telegram', 42);

  const data = await createdTelegram(payload);
  expect(data.agent_id).toBe(getTestAgentId());
  expect(data.channel).toBe('telegram');
  expect(data.direction).toBe('boss_to_agent');
  expect(data.body).toBe('Hello from telegram');
  expect(data.metadata?.message).toBeDefined();
});

telegramCase('strips caller-supplied answered_by from telegram text metadata', async () => {
  const data = await createdTelegram({
    update_id: 4201,
    answered_by: { client_id: 'forged', kind: 'ios', label: 'Forged device' },
    message: {
      message_id: 4201,
      chat: { id: 'test-chat', type: 'private' },
      text: 'Telegram metadata boundary',
      from: { id: 1, is_bot: false },
    },
  });
  expect(data.metadata).toMatchObject({
    update_id: 4201,
    message: {
      message_id: 4201, chat: { id: 'test-chat', type: 'private' },
      text: 'Telegram metadata boundary', from: { id: 1, is_bot: false },
    },
    source: 'telegram',
    provenance: {
      source: 'telegram', signature: { status: 'unsupported' },
      authentication: { kind: 'provider_account', credential_id: '1' },
    },
  });
  expect(data.metadata?.['answered_by']).toBeUndefined();
});

telegramCase('creates a boss_to_agent message from /msg command text', async () => {
  const payload = {
    update_id: 6001,
    message: {
      message_id: 601,
      chat: { id: 'test-chat', type: 'private' },
      text: '/msg Deploy the hotfix',
      entities: [{ type: 'bot_command', offset: 0, length: 4 }],
      from: { id: 1, is_bot: false },
    },
  };

  const data = await createdTelegram(payload);
  expect(data.direction).toBe('boss_to_agent');
  expect(data.body).toBe('Deploy the hotfix');
});

telegramCase('sends session status back to telegram for /status commands', async () => {
  const fetchMock = vi.fn()
    .mockResolvedValueOnce(new Response('{}', { status: 200 }))
    .mockResolvedValueOnce(new Response(JSON.stringify({ result: { message_id: 901 } }), { status: 200 }));
  vi.stubGlobal('fetch', fetchMock);
  await env.DB.prepare(
    "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, status_text, last_seen_at) VALUES (?, " +
    "?, ?, ?, ?, datetime('now'))"
  )
    .bind('status-session-1', getTestAgentId(), 'main', 'working', 'building')
    .run();
  await env.DB.prepare(
    "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, status_text, last_seen_at) VALUES (?, " +
    "?, ?, ?, ?, datetime('now'))"
  )
    .bind('status-session-2', getTestAgentId(), 'review', 'blocked', 'waiting for approval')
    .run();

  const res = await postTelegramWebhook({
    update_id: 6002,
    message: {
      message_id: 602,
      chat: { id: 'test-chat', type: 'private' },
      text: '/status',
      entities: [{ type: 'bot_command', offset: 0, length: 7 }],
      from: { id: 1, is_bot: false },
    },
  });

  expect(res.status).toBe(200);
  expect(fetchMock).toHaveBeenCalledTimes(2);
  const sendCall = fetchMock.mock.calls[1] as [RequestInfo | URL, RequestInit];
  const sendPayload = JSON.parse(String(sendCall[1].body)) as { chat_id: string; text: string };
  expect(sendPayload.chat_id).toBe('test-chat');
  expect(sendPayload.text).toContain('test-agent');
  expect(sendPayload.text).toContain('2 active session');
  expect(sendPayload.text).toContain('main: working (building)');
  expect(sendPayload.text).toContain('review: blocked (waiting for approval)');
});

telegramCase('targets the matching session when a telegram forum topic maps to telegram_topic_id',
async () => {
  await env.DB.prepare(
    "INSERT OR REPLACE INTO sessions (id, agent_id, label, status, telegram_topic_id) VALUES (?, ?, ?, " +
    "'working', ?)"
  )
    .bind('tg-topic-session-1', getTestAgentId(), 'topic-session', 4444)
    .run();

  const data = await createdTelegram({
    message: {
      message_id: 43,
      message_thread_id: 4444,
      chat: { id: 'test-chat', type: 'supergroup' },
      text: 'Topic scoped hello',
      from: { id: 1, is_bot: false },
    },
  });
  expect(data.target_session_id).toBe('tg-topic-session-1');
  expect(data.body).toBe('Topic scoped hello');
  const event = await env.DB.prepare(
    "SELECT session_id FROM session_events WHERE raw LIKE '%Topic scoped hello%' ORDER BY sequence DESC " +
    "LIMIT 1",
  ).first<{ session_id: string }>();
  expect(event?.session_id).toBe('tg-topic-session-1');
});

telegramCase('returns 400 when chat is missing', returnsStatus(400, () =>
  postTelegramWebhook({ message: { text: 'no chat' } })));

telegramCase('returns 400 when body is missing', returnsStatus(400, () =>
  postTelegramWebhook({ message: { chat: { id: 'test-chat' } } })));

telegramCase('returns 403 for unknown chat_id', returnsStatus(403, () => postTelegramWebhook({
    message: {
      chat: { id: 'missing-chat' },
      text: 'hello',
    },
  })));

telegramCase('ignores bot messages', async () => {
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

telegramCase('links reply_to when boss swipe-replies to an agent message', async () => {
  const parentId = 'reply-link-test-parent-001';
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) " +
    "VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', 'Question?', 'delivered', 'normal', ?)"
  )
    .bind(parentId, getTestAgentId(), JSON.stringify({ telegram_message_id: 777 }))
    .run();

  const payload = telegramText('My reply', 888, { message_id: 777 });

  const data = await createdTelegram(payload);
  expect(data.reply_to).toBe(parentId);
  expect(data.body).toBe('My reply');
});

telegramCase('sets reply_to null when reply_to_message matches no stored message', async () => {
  const payload = telegramText('Reply to unknown', 999, { message_id: 99999 });

  const data = await createdTelegram(payload);
  expect(data.reply_to).toBeNull();
});

telegramCase('auto-links standalone message to pending blocking message', async () => {
  // Mark any existing blocking messages as replied so they don't interfere
  await env.DB.prepare(
    "UPDATE messages SET status = 'replied' WHERE agent_id = ? AND mode = 'blocking' AND status IN " +
    "('sent', 'delivered')"
  )
    .bind(getTestAgentId())
    .run();
  const blockingId = 'auto-link-blocking-001';
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority) VALUES (?, ?, " +
    "'agent_to_boss', 'blocking', 'telegram', 'Pick option', 'delivered', 'normal')"
  )
    .bind(blockingId, getTestAgentId())
    .run();

  // No reply_to_message — boss typed a standalone message
  const payload = telegramText('I choose option B', 2001);

  const data = await createdTelegram(payload);
  expect(data.reply_to).toBe(blockingId);
});

telegramCase('does not auto-link when no pending blocking message exists', async () => {
  // Clean up any blocking messages first
  await env.DB.prepare(
    "UPDATE messages SET status = 'replied' WHERE agent_id = ? AND mode = 'blocking' AND status IN " +
    "('sent', 'delivered')"
  )
    .bind(getTestAgentId())
    .run();

  const payload = telegramText('Just a regular message', 2002);

  const data = await createdTelegram(payload);
  expect(data.reply_to).toBeNull();
});
