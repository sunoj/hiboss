// Admin integration tests covering channel delivery stats diagnostics.
// Exports GET /api/channels/stats checks for summary and verbose responses.
// Depends on the cloudflare:test runtime and shared auth/seed helpers.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';

const API_BASE = 'https://test.local/api';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('UPDATE api_keys SET role = ? WHERE id = ?')
    .bind('admin', getTestAgentId())
    .run();
});

describe('GET /api/channels/stats', () => {
  it('returns per-channel delivery stats', async () => {
    await resetChannelStatsFixtures();
    await env.DB
      .prepare('INSERT INTO channel_configs (agent_id, channel, config, enabled) VALUES (?, ?, ?, 1)')
      .bind(getTestAgentId(), 'email', JSON.stringify({ smtp_host: 'smtp.example.com' }))
      .run();
    await insertMessage('discord-delivered', 'agent_to_boss', 'discord', 'Discord ok', 'delivered', null, '2026-04-04 09:58:00', '2026-04-04 10:00:00');
    await insertMessage('discord-failed', 'boss_to_agent', 'discord', 'Discord fail', 'sent', { delivery_error: 'discord webhook failed 403' }, '2026-04-03 15:25:00', '2026-04-03 15:30:00');
    await insertMessage('telegram-read', 'agent_to_boss', 'telegram', 'Telegram ok', 'read', null, '2026-04-04 10:02:00', '2026-04-04 10:05:00');

    const res = await SELF.fetch(`${API_BASE}/channels/stats`, { headers: authHeaders() });

    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      channels: [
        {
          channel: 'discord',
          total_sent: 2,
          total_delivered: 1,
          total_failed: 1,
          last_delivery_at: '2026-04-04T10:00:00Z',
          last_error: 'discord webhook failed 403',
          last_error_at: '2026-04-03T15:30:00Z',
        },
        {
          channel: 'email',
          total_sent: 0,
          total_delivered: 0,
          total_failed: 0,
          last_delivery_at: null,
          last_error: null,
          last_error_at: null,
        },
        {
          channel: 'telegram',
          total_sent: 1,
          total_delivered: 1,
          total_failed: 0,
          last_delivery_at: '2026-04-04T10:05:00Z',
          last_error: null,
          last_error_at: null,
        },
      ],
    });
  });

  it('adds verbose delivery diagnostics when requested', async () => {
    await env.DB
      .prepare("CREATE TABLE IF NOT EXISTS delivery_queue (id TEXT PRIMARY KEY, agent_id TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')))")
      .run();
    await env.DB
      .prepare("INSERT INTO delivery_queue (id, agent_id, status, created_at) VALUES (?, ?, ?, ?), (?, ?, ?, ?)")
      .bind('dq-1', getTestAgentId(), 'pending', '2026-04-04 09:00:00', 'dq-2', getTestAgentId(), 'retrying', '2026-04-04 09:30:00')
      .run();

    const res = await SELF.fetch(`${API_BASE}/channels/stats?verbose=1`, { headers: authHeaders() });

    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({
      recent_errors: [
        {
          channel: 'discord',
          last_error: 'discord webhook failed 403',
          last_error_at: '2026-04-03T15:30:00Z',
          message_id: 'discord-failed',
        },
      ],
      delivery_queue: {
        total: 2,
        by_status: [
          { status: 'pending', total: 1 },
          { status: 'retrying', total: 1 },
        ],
        oldest_at: '2026-04-04T09:00:00Z',
      },
      direction_counts: [
        { channel: 'discord', direction: 'agent_to_boss', total: 1 },
        { channel: 'discord', direction: 'boss_to_agent', total: 1 },
        { channel: 'telegram', direction: 'agent_to_boss', total: 1 },
      ],
    });
  });
});

async function resetChannelStatsFixtures(): Promise<void> {
  await env.DB.prepare('DELETE FROM channel_configs WHERE agent_id = ?').bind(getTestAgentId()).run();
  await env.DB.prepare('DELETE FROM messages WHERE agent_id = ?').bind(getTestAgentId()).run();
  await env.DB.prepare('DROP TABLE IF EXISTS delivery_queue').run();
}

async function insertMessage(
  id: string,
  direction: string,
  channel: string,
  body: string,
  status: string,
  metadata: Record<string, unknown> | null,
  createdAt: string,
  updatedAt: string
): Promise<void> {
  await env.DB
    .prepare(
      'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, metadata, created_at, updated_at) VALUES (?, ?, ?, \'async\', ?, ?, ?, ?, ?, ?)'
    )
    .bind(id, getTestAgentId(), direction, channel, body, status, metadata ? JSON.stringify(metadata) : null, createdAt, updatedAt)
    .run();
}
