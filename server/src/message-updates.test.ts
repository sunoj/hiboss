// Worker integration tests for migration 0054's automatic message timestamps.
// Exercises reactions, option expiry, and scheduled delivery with D1.
import { testRequest } from './test-request';
import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { persistDiscordReaction } from './discord-gateway-reactions';
import { handleScheduled } from './scheduled';
import { authHeaders, getTestAgentId, seedDatabase } from './test-helpers';

const OLD = '2000-01-01 00:00:00';
const SECRET = 'message-updates-test-secret';

beforeAll(async () => {
  await seedDatabase();
  env.TELEGRAM_WEBHOOK_SECRET = SECRET;
  await env.DB.prepare(
    "INSERT INTO bosses (id, name, role, discord_user_id, telegram_user_id) VALUES (?, ?, 'manager', ?, ?)"
  ).bind('updates-boss', 'Updates Boss', 'updates-discord-boss', 'updates-telegram-boss').run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind('updates-boss', getTestAgentId()).run();
  for (const [channel, config] of [
    ['discord', { channel_id: 'updates-discord-chat' }],
    ['telegram', { chat_id: 'updates-telegram-chat' }],
    ['api', {}],
  ] as const) {
    await env.DB.prepare('INSERT INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)')
      .bind(getTestAgentId(), channel, JSON.stringify(config)).run();
  }
  // Backdate only these inserts so a later write in the same request must move the timestamp.
  await env.DB.prepare(`CREATE TRIGGER backdate_expiry_fixture AFTER INSERT ON messages
    WHEN NEW.body LIKE 'updates-expiry-%'
    BEGIN UPDATE messages SET updated_at = '${OLD}' WHERE id = NEW.id; END;`).run();
});

async function insertMessage(
  id: string, channel = 'api', metadata: Record<string, unknown> = {},
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO messages (id, agent_id, direction, mode, channel, body, updated_at, metadata)
      VALUES (?, ?, 'agent_to_boss', 'async', ?, ?, ?, ?)`
  ).bind(id, getTestAgentId(), channel, 'Track changes', OLD, JSON.stringify(metadata)).run();
}

async function timestamp(id: string): Promise<string> {
  const row = await env.DB.prepare('SELECT updated_at FROM messages WHERE id = ?')
    .bind(id).first<{ updated_at: string }>();
  if (!row) throw new Error('missing message');
  return row.updated_at;
}

// Both sides use SQLite's fixed "YYYY-MM-DD HH:MM:SS" form, so string order is time order.
async function expectMoved(id: string): Promise<void> {
  const value = await timestamp(id);
  expect(value > OLD, `${id} updated_at is ${value}`).toBe(true);
}

async function expectSendExpiryUpdate(): Promise<void> {
  for (const options of [undefined, ['Approve', 'Reject']]) {
    const response = await testRequest('POST', 'https://test.local/api/messages', authHeaders(), {
        body: `updates-expiry-${options ? 'options' : 'control'}`,
        to: 'test-agent', channel: 'api', options,
      });
    expect(response.status).toBe(201);
    const message = await response.json() as { id: string };
    if (options) {
      await expectMoved(message.id);
      const row = await env.DB.prepare('SELECT expires_at FROM messages WHERE id = ?')
        .bind(message.id).first<{ expires_at: string | null }>();
      expect(row?.expires_at).toBeTruthy();
    } else {
      expect(await timestamp(message.id)).toBe(OLD);
    }
  }
}

describe('message update timestamps', () => {
  it('moves updated_at through Discord, Telegram, option expiry, and scheduled delivery writes', async () => {
    await insertMessage('updates-discord', 'discord', { discord_message_id: 'updates-external' });
    expect(await persistDiscordReaction(env, getTestAgentId(), {
      user_id: 'updates-discord-boss', channel_id: 'updates-discord-chat',
      message_id: 'updates-external', emoji: { id: null, name: '👍' },
    }, 'add')).toBe(true);
    await expectMoved('updates-discord');

    await insertMessage('updates-telegram', 'telegram', { telegram_message_id: 101 });
    const response = await testRequest('POST', 'https://test.local/api/webhooks/telegram',
      { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': SECRET },
      { message_reaction: {
        chat: { id: 'updates-telegram-chat' }, message_id: 101,
        user: { id: 'updates-telegram-boss', first_name: 'Boss' },
        new_reaction: [{ type: 'emoji', emoji: '👍' }],
      } });
    expect(response.status).toBe(200);
    await expectMoved('updates-telegram');
    await expectSendExpiryUpdate();

    await insertMessage('updates-scheduled');
    await env.DB.prepare(
      `INSERT INTO delivery_queue (message_id, agent_id, channel, config, scheduled_at)
        VALUES (?, ?, 'api', '{}', ?)`
    ).bind('updates-scheduled', getTestAgentId(), OLD).run();
    await handleScheduled(env);
    await expectMoved('updates-scheduled');
    expect(await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
      .bind('updates-scheduled').first()).toEqual({ status: 'delivered' });
  });

  it('preserves a timestamp explicitly changed by the statement', async () => {
    await insertMessage('updates-explicit');
    const explicit = '2001-02-03 04:05:06';
    await env.DB.prepare('UPDATE messages SET body = ?, updated_at = ? WHERE id = ?')
      .bind('Explicit change', explicit, 'updates-explicit').run();
    expect(await timestamp('updates-explicit')).toBe(explicit);
  });

  it('timestamps metadata, body, expiry, and no-op updates without recursive writes', async () => {
    await insertMessage('updates-repeat');
    const assignments = ["metadata = '{}'", "body = 'changed'", "expires_at = '2099-01-01'", 'body = body'];
    for (const assignment of assignments) {
      await env.DB.prepare('UPDATE messages SET updated_at = ? WHERE id = ?')
        .bind(OLD, 'updates-repeat').run();
      await env.DB.prepare(`UPDATE messages SET ${assignment} WHERE id = ?`).bind('updates-repeat').run();
      expect(await timestamp('updates-repeat')).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
      await expectMoved('updates-repeat');
    }
    await env.DB.prepare('UPDATE messages SET body = body WHERE id = ?').bind('updates-repeat').run();
    await expectMoved('updates-repeat');
  });

  it('indexes agent-scoped timestamp ranges', async () => {
    const plan = await env.DB.prepare(
      'EXPLAIN QUERY PLAN SELECT id FROM messages WHERE agent_id IN (?, ?) AND updated_at >= ?'
    ).bind(getTestAgentId(), 'another-agent', OLD).all<{ detail: string }>();
    expect(plan.results.some(row => row.detail.includes('idx_messages_agent_updated'))).toBe(true);
  });
});
