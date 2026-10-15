// Integration tests for Discord gateway lookup and reaction persistence helpers.
// Covers channel-to-agent resolution plus reaction add/remove metadata updates.
// Depends on cloudflare:test env, seeded D1 tables, and discord-gateway-reactions.

import { beforeAll, describe, expect, it } from 'vitest';
import { env } from 'cloudflare:test';
import { hashApiKey } from './middleware/auth';
import { persistDiscordReaction, lookupDiscordAgentId } from './discord-gateway-reactions';
import { getTestAgentId, seedDatabase } from './test-helpers';

const THREAD_AGENT_ID = 'discord-thread-agent';
const THREAD_SESSION_ID = 'discord-thread-session';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(getTestAgentId(), 'discord', '{"channel_id":"test-discord-ch","bot_token":"fake-token"}')
    .run();
  const keyHash = await hashApiKey('hb_discord_thread_key');
  await env.DB.prepare(
    'INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)'
  )
    .bind(THREAD_AGENT_ID, 'discord-thread-agent', keyHash)
    .run();
  await env.DB.prepare(
    'INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, ?, ?)'
  )
    .bind(THREAD_AGENT_ID, 'discord', '{"channel_id":"thread-parent","bot_token":"fake-token"}')
    .run();
  for (const userId of ['boss-user-1', 'boss-user-2']) {
    await env.DB.prepare("INSERT INTO bosses (id, name, role, discord_user_id) VALUES (?, ?, 'manager', ?)")
      .bind(userId, userId, userId).run();
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(userId, getTestAgentId()).run();
  }
  await env.DB.prepare(
    'INSERT OR IGNORE INTO sessions (id, agent_id, discord_thread_id) VALUES (?, ?, ?)'
  )
    .bind(THREAD_SESSION_ID, THREAD_AGENT_ID, 'thread-child')
    .run();
});

describe('discord-gateway-reactions', () => {
  it('finds agent ids for configured discord channels and thread sessions', async () => {
    await expect(lookupDiscordAgentId(env, 'test-discord-ch')).resolves.toBe(getTestAgentId());
    await expect(lookupDiscordAgentId(env, 'thread-child')).resolves.toBe(THREAD_AGENT_ID);
    await expect(lookupDiscordAgentId(env, 'missing-channel')).resolves.toBeNull();
  });

  it('adds reactions using top-level discord_message_id metadata', async () => {
    const messageId = 'discord-reaction-top-level';
    await env.DB.prepare(
      "INSERT OR REPLACE INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'discord', 'Question?', 'delivered', 'normal', ?)"
    )
      .bind(messageId, getTestAgentId(), JSON.stringify({ discord_message_id: 'discord-msg-top' }))
      .run();

    const updated = await persistDiscordReaction(env, getTestAgentId(), {
      user_id: 'boss-user-1',
      channel_id: 'test-discord-ch',
      message_id: 'discord-msg-top',
      emoji: { id: null, name: '🔥' },
    }, 'add');

    expect(updated).toBe(true);
    await expect(readReactions(messageId)).resolves.toEqual([{
      emoji: '🔥', actor: 'boss', actor_id: 'boss-user-1', created_at: expect.any(String),
    }]);
  });

  it('preserves mixed reactions on duplicate adds and removes only the Discord boss reaction', async () => {
    const messageId = 'discord-reaction-mixed';
    const preserved = [
      { emoji: '🔥', actor: 'agent', actor_id: 'boss-user-1', created_at: '2026-01-01' },
      { emoji: '🔥', user: 'boss-user-2' },
      { emoji: '🔥', actor: 'boss', actor_id: 'other-boss', created_at: '2026-01-02' },
      { emoji: '✅', actor: 'boss', actor_id: 'boss-user-1', created_at: '2026-01-03' },
    ];
    await env.DB.prepare(`INSERT INTO messages
      (id, agent_id, direction, mode, channel, body, metadata)
      VALUES (?, ?, 'agent_to_boss', 'async', 'discord', 'Mixed reactions', ?)`)
      .bind(messageId, getTestAgentId(), JSON.stringify({
        discord_message_id: 'discord-msg-mixed', reactions: preserved, keep: 'unchanged',
      })).run();
    const reaction = {
      user_id: 'boss-user-1', channel_id: 'test-discord-ch', message_id: 'discord-msg-mixed',
      emoji: { id: null, name: '🔥' },
    };
    expect(await persistDiscordReaction(env, getTestAgentId(), reaction, 'add')).toBe(true);
    const added = [...preserved, {
      emoji: '🔥', actor: 'boss', actor_id: 'boss-user-1', created_at: expect.any(String),
    }];
    await expect(readReactions(messageId)).resolves.toEqual(added);
    expect(await persistDiscordReaction(env, getTestAgentId(), reaction, 'add')).toBe(true);
    await expect(readReactions(messageId)).resolves.toEqual(added);
    expect(await persistDiscordReaction(env, getTestAgentId(), reaction, 'remove')).toBe(true);
    await expect(readReactions(messageId)).resolves.toEqual(preserved);
    const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?')
      .bind(messageId).first<{ metadata: string }>();
    expect(JSON.parse(row!.metadata)).toMatchObject({ keep: 'unchanged' });
  });

  it('removes matching reactions using nested discord_msg.id metadata', async () => {
    const messageId = 'discord-reaction-nested';
    await env.DB.prepare(
      "INSERT OR REPLACE INTO messages (id, agent_id, direction, mode, channel, body, status, priority, metadata) VALUES (?, ?, 'agent_to_boss', 'blocking', 'discord', 'Question?', 'delivered', 'normal', ?)"
    )
      .bind(messageId, getTestAgentId(), JSON.stringify({
        discord_msg: { id: 'discord-msg-nested' },
        reactions: [
          { emoji: '🔥', user: 'boss-user-1' },
          { emoji: '✅', user: 'boss-user-2' },
        ],
      }))
      .run();

    expect(await persistDiscordReaction(env, getTestAgentId(), {
      user_id: 'boss-user-1', channel_id: 'test-discord-ch', message_id: 'discord-msg-nested',
      emoji: { id: null, name: '🔥' },
    }, 'add')).toBe(true);
    await expect(readReactions(messageId)).resolves.toEqual([
      { emoji: '🔥', user: 'boss-user-1' }, { emoji: '✅', user: 'boss-user-2' },
    ]);

    const updated = await persistDiscordReaction(env, getTestAgentId(), {
      user_id: 'boss-user-1',
      channel_id: 'test-discord-ch',
      message_id: 'discord-msg-nested',
      emoji: { id: null, name: '🔥' },
    }, 'remove');

    expect(updated).toBe(true);
    await expect(readReactions(messageId)).resolves.toEqual([{ emoji: '✅', user: 'boss-user-2' }]);
  });
});

async function readReactions(messageId: string): Promise<unknown> {
  const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?').bind(messageId).first<{ metadata: string | null }>();
  return row?.metadata ? (JSON.parse(row.metadata) as Record<string, unknown>)['reactions'] : null;
}
