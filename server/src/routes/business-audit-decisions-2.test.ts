// Decision integrity regressions for cron, option streams, and signed webhooks.
// Covers queued defaults, answer provenance, Discord replay, and Telegram chat binding.
// Depends on SELF, seeded D1 fixtures, scheduled delivery, and option expiry.

import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import type { Env, MessageRow } from '../types';
import { getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { handleScheduled } from '../scheduled';
import { expireMessageOptions } from './message-options';

const base = 'https://test.local';
const agent = getTestAgentId();
const token = 'decision-audit-stream-token';
const bossHeaders = { Authorization: `Bearer ${token}` };
const fresh = (name: string) => `d-${name}-${crypto.randomUUID().slice(0, 8)}`;

async function option(id: string, defaults = false): Promise<MessageRow> {
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata, expires_at)
    VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Choose', 'sent', ?, ?)`)
    .bind(id, agent, JSON.stringify({ options: ['Yes', 'No'], ...(defaults ? { default_option: 'No' } : {}) }),
      new Date(Date.now() + 60_000).toISOString()).run();
  const row = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!row) throw new Error('option fixture missing');
  return row;
}

async function answerCount(id: string): Promise<number> {
  const row = await env.DB.prepare('SELECT COUNT(*) AS total FROM messages WHERE reply_to = ?')
    .bind(id).first<{ total: number }>();
  return row?.total ?? 0;
}

beforeAll(async () => {
  await seedDatabase();
  const boss = await seedBossToken('Decision stream boss', 'manager', token, fresh('stream-boss'));
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, agent).run();
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('decision integrity: scheduled and webhook paths', () => {
  it('F19 queued delivery preserves a resolved default and does not default twice', async () => {
    const control = await option(fresh('f19-control'), true);
    await expireMessageOptions(env as Env, agent, control);
    expect(await answerCount(control.id)).toBe(1);
    expect((await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(control.id)
      .first<{ status: string }>())?.status).toBe('replied');
    const target = await option(fresh('f19-target'), true);
    await env.DB.prepare(`UPDATE messages SET expires_at = datetime('now', '-1 minute') WHERE id = ?`)
      .bind(target.id).run();
    const config = JSON.stringify({ native_only: true });
    await env.DB.prepare(`INSERT INTO delivery_queue
      (id, message_id, agent_id, channel, config, scheduled_at)
      VALUES (?, ?, ?, 'api', ?, datetime('now', '-1 minute'))`)
      .bind(fresh('f19-queue'), target.id, agent, config).run();
    expect(await answerCount(target.id)).toBe(0);
    await handleScheduled(env as Env);
    expect(await answerCount(target.id)).toBe(1);
    // The ask resolved before its queued send, so the drain skips it instead of delivering.
    expect(await env.DB.prepare('SELECT status, error FROM delivery_queue WHERE message_id = ?').bind(target.id)
      .first()).toEqual({ status: 'failed', error: 'ask closed before delivery' });
    const firstStatus = (await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(target.id)
      .first<{ status: string }>())?.status;
    await handleScheduled(env as Env);
    expect({ firstStatus, answersAfterSecondRun: await answerCount(target.id) })
      .toEqual({ firstStatus: 'replied', answersAfterSecondRun: 1 });
  });

  it('F20 option stream identifies auto-default as a system answer', async () => {
    const id = fresh('f20');
    const row = await option(id, true);
    const response = await SELF.fetch(`${base}/api/boss/stream?options=true`, { headers: bossHeaders });
    expect(response.status).toBe(200);
    const reader = response.body?.getReader();
    if (!reader) throw new Error('option stream missing');
    try {
      const first = new TextDecoder().decode((await reader.read()).value);
      expect(first).toContain(id);
      await expireMessageOptions(env as Env, agent, row);
      const persisted = await env.DB.prepare('SELECT metadata FROM messages WHERE reply_to = ?')
        .bind(id).first<{ metadata: string }>();
      expect(JSON.parse(persisted?.metadata ?? '{}')).toMatchObject({ auto_default: true });
      const resolved = new TextDecoder().decode((await reader.read()).value);
      expect(resolved).toContain(`"id":"${id}"`);
      expect(resolved).toContain('"answer":"No"');
      expect(resolved).not.toContain('"source":"api"');
    } finally {
      await reader.cancel();
    }
  });

});
