// Telegram callback actions, missing configuration and reaction authorization.
// Registers webhook cases using the shared root hooks and synthetic fixtures.

import { env, SELF } from 'cloudflare:test';
import { expect } from 'vitest';
import { getTestAgentId } from '../../test-helpers';
import {
  TELEGRAM_SECRET, telegramCase, postTelegramWebhook, telegramCallback, createdTelegram,
} from './support';

telegramCase('handles inline keyboard callback queries', async () => {
  const parentId = 'ca11bacf00000001aabbccdd00000001';
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, metadata) VALUES (?, " +
    "?, 'agent_to_boss', 'blocking', 'Original', 'sent', 'normal', ?)"
  )
    .bind(parentId, getTestAgentId(), JSON.stringify({ options: ['option-one'] }))
    .run();

  const data = await createdTelegram(telegramCallback('cb-1', 'ca11bacf:option-one', 100, 'Choose option'));
  expect(data.channel).toBe('telegram');
  expect(data.reply_to).toBe(parentId);
  expect(data.body).toBe('option-one');
});

telegramCase('copies action from parent metadata to callback reply', async () => {
  const parentId = 'ac710cba00000002aabbccdd00000002';
  const actions = { Approve: 'aid merge t-123', Reject: 'echo rejected' };
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, metadata) VALUES (?, " +
    "?, 'agent_to_boss', 'blocking', 'Deploy?', 'delivered', 'normal', ?)"
  )
    .bind(parentId, getTestAgentId(), JSON.stringify({ options: Object.keys(actions), actions }))
    .run();

  const data = await createdTelegram(telegramCallback('cb-action-1', 'ac710cba:Approve', 200, 'Deploy?'));
  expect(data.reply_to).toBe(parentId);
  expect(data.body).toBe('Approve');
  expect(data.metadata?.action).toBe('aid merge t-123');
});

telegramCase('callback reply has no action metadata when parent has no actions', async () => {
  const parentId = 'a0ac7100000000030000000000000003';
  await env.DB.prepare(
    "INSERT INTO messages (id, agent_id, direction, mode, body, status, priority, metadata) VALUES (?, " +
    "?, 'agent_to_boss', 'async', 'No actions', 'sent', 'normal', ?)"
  )
    .bind(parentId, getTestAgentId(), JSON.stringify({ options: ['SomeOption'] }))
    .run();

  const data = await createdTelegram(
    telegramCallback('cb-no-action', 'a0ac7100:SomeOption', 201, 'No actions'),
  );
  expect(data.reply_to).toBe(parentId);
  expect(data.body).toBe('SomeOption');
  expect(data.metadata?.action).toBeUndefined();
  expect(data.metadata).toMatchObject({
    source: 'telegram',
    provenance: {
      source: 'telegram',
      signature: { status: 'unsupported' },
    },
  });
});

telegramCase('returns 500 when telegram webhook secret is unset', async () => {
  env.TELEGRAM_WEBHOOK_SECRET = undefined;

  const res = await SELF.fetch('https://test.local/api/webhooks/telegram', {
    method: 'POST',
    body: JSON.stringify({ message: { chat: { id: 'test-chat' }, text: 'hello' } }),
  });

  expect(res.status).toBe(500);
  expect(await res.text()).toBe('webhook secret not configured');

  env.TELEGRAM_WEBHOOK_SECRET = TELEGRAM_SECRET;
});

telegramCase('rejects reaction updates from unauthorized telegram bosses', async () => {
  // Insert a boss so that boss-auth mode is active (open access when no bosses exist)
  await env.DB.prepare(
    "INSERT OR IGNORE INTO bosses (id, name, role, telegram_user_id) VALUES (?, ?, ?, ?)"
  ).bind('boss-reaction-test', 'Reaction Boss', 'admin', 'known-boss-user').run();

  const reactionMessageId = 'reaction-auth-test-001';
  await env.DB.prepare(
    "INSERT OR IGNORE INTO messages (id, agent_id, direction, mode, channel, body, status, priority, " +
    "metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'telegram', 'Question?', 'delivered', 'normal', ?)"
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

  // Clean up to avoid affecting other tests
  await env.DB.prepare('DELETE FROM bosses WHERE id = ?').bind('boss-reaction-test').run();
});
