// Round-two ask integrity regressions across API, Telegram, and Discord writers.
// Covers one-answer races, unlinked late text, and ignored inserts.
// Depends on seeded D1 fixtures, SELF routes, and the real default resolver.

import { testRequest } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import type { Env, MessageRow } from '../types';
import { seedBossToken, seedDatabase } from '../test-helpers';
import { expireMessageOptions } from './message-options';

const base = 'https://test.local';
const token = 'ask-r2-boss-token';
const fresh = () => crypto.randomUUID().replaceAll('-', '');
const bossHeaders = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
let bossId: string;

async function agentWithGrant(): Promise<{ agent: string }> {
  const agent = fresh();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(agent, agent, fresh()).run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agent).run();
  return { agent };
}

async function ask(agent: string, channel: 'api' | 'telegram' | 'discord', metadata: Record<string, unknown> = {}): Promise<MessageRow> {
  const id = fresh();
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata, expires_at)
    VALUES (?, ?, 'agent_to_boss', 'blocking', ?, 'Choose', 'delivered', ?, ?)`)
    .bind(id, agent, channel, JSON.stringify(metadata), new Date(Date.now() + 60_000).toISOString()).run();
  const row = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!row) throw new Error('ask fixture missing');
  return row;
}

async function answers(id: string): Promise<{ body: string; reply_to: string | null }[]> {
  const rows = await env.DB.prepare("SELECT body, reply_to FROM messages WHERE reply_to = ? AND direction = 'boss_to_agent'")
    .bind(id).all<{ body: string; reply_to: string | null }>();
  return rows.results;
}

async function reply(id: string, body: string): Promise<Response> {
  return testRequest('POST', `${base}/api/boss/messages/${id}/reply`, bossHeaders, { body });
}

beforeAll(async () => {
  await seedDatabase();
  bossId = await seedBossToken('Ask R2 boss', 'manager', token, fresh());
});

afterEach(() => vi.unstubAllGlobals());

describe('one answer per ask across writers', () => {
  it('returns 409 for a second boss API answer to an optionless blocking ask', async () => {
    const { agent } = await agentWithGrant();
    const control = await ask(agent, 'api');
    expect((await reply(control.id, 'First')).status).toBe(201);
    expect(await answers(control.id)).toEqual([{ body: 'First', reply_to: control.id }]);
    const target = await ask(agent, 'api');
    expect((await reply(target.id, 'Yes')).status).toBe(201);
    expect((await reply(target.id, 'No')).status).toBe(409);
    expect(await answers(target.id)).toEqual([{ body: 'Yes', reply_to: target.id }]);
  });

  it('keeps an ask open when a trigger ignores its reply insert', async () => {
    const { agent } = await agentWithGrant();
    const control = await ask(agent, 'api', { options: ['Yes'] });
    expect((await reply(control.id, 'Yes')).status).toBe(201);
    expect(await answers(control.id)).toHaveLength(1);
    const target = await ask(agent, 'api', { options: ['Yes'] });
    const trigger = `ignore_${fresh()}`;
    await env.DB.prepare(`CREATE TRIGGER ${trigger} BEFORE INSERT ON messages
      WHEN NEW.reply_to = '${target.id}' BEGIN SELECT RAISE(IGNORE); END`).run();
    try {
      expect((await reply(target.id, 'Yes')).status).toBeGreaterThanOrEqual(500);
      expect(await answers(target.id)).toEqual([]);
      const parent = await env.DB.prepare('SELECT status FROM messages WHERE id = ?')
        .bind(target.id).first<{ status: string }>();
      expect(parent?.status).toBe('delivered');
    } finally {
      await env.DB.prepare(`DROP TRIGGER ${trigger}`).run();
    }
  });
});
