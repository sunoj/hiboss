// Decision integrity regressions for agent and boss message routes.
// Covers reply ownership, option claims, status transitions, and expiry races.
// Depends on SELF, seeded D1 fixtures, and the real option expiry helper.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import type { Env, MessageRow } from '../types';
import { hashApiKey } from '../middleware/auth';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';
import { expireMessageOptions } from './message-options';

const base = 'https://test.local';
const agent = getTestAgentId();
const bossToken = 'decision-audit-boss-token';
const bossHeaders = { Authorization: `Bearer ${bossToken}`, 'Content-Type': 'application/json' };
const fresh = (name: string) => `d-${name}-${crypto.randomUUID().slice(0, 8)}`;
const request = (path: string, method: string, body: unknown, headers = authHeaders()) =>
  SELF.fetch(`${base}${path}`, { method, headers, body: JSON.stringify(body) });

async function ask(id: string, options?: string[], extra: Record<string, unknown> = {}): Promise<MessageRow> {
  const metadata = options ? JSON.stringify({ options, ...extra }) : null;
  const expires = options ? new Date(Date.now() + 60_000).toISOString() : null;
  await env.DB.prepare(`INSERT INTO messages
    (id, agent_id, direction, mode, channel, body, status, metadata, expires_at)
    VALUES (?, ?, 'agent_to_boss', 'blocking', 'api', 'Choose', 'sent', ?, ?)`)
    .bind(id, agent, metadata, expires).run();
  const row = await env.DB.prepare('SELECT * FROM messages WHERE id = ?').bind(id).first<MessageRow>();
  if (!row) throw new Error('ask fixture missing');
  return row;
}

async function replies(id: string): Promise<{ body: string; direction: string }[]> {
  const rows = await env.DB.prepare('SELECT body, direction FROM messages WHERE reply_to = ? ORDER BY created_at, id')
    .bind(id).all<{ body: string; direction: string }>();
  return rows.results;
}

async function status(id: string): Promise<string | null> {
  return (await env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(id)
    .first<{ status: string }>())?.status ?? null;
}

beforeAll(async () => {
  await seedDatabase();
  const boss = await seedBossToken('Decision audit boss', 'manager', bossToken, fresh('boss'));
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(boss, agent).run();
});

describe('decision integrity: message routes', () => {
  it('F1 agent cannot reply to its own ask as boss', async () => {
    const legitimate = fresh('f1-control');
    const target = fresh('f1-target');
    await ask(legitimate);
    await ask(target);
    expect((await request(`/api/boss/messages/${legitimate}/reply`, 'POST', { body: 'Boss answer' }, bossHeaders)).status).toBe(201);
    expect(await replies(legitimate)).toEqual([{ body: 'Boss answer', direction: 'boss_to_agent' }]);
    const attack = await request(`/api/messages/${target}/reply`, 'POST', { body: 'Agent answer' });
    expect(attack.status).toBeGreaterThanOrEqual(400);
    expect(await status(target)).toBe('sent');
    expect(await replies(target)).toEqual([]);
  });

  it('F7 agent cannot mark its own ask replied without an answer', async () => {
    const id = fresh('f7');
    await ask(id);
    expect((await request(`/api/messages/${id}`, 'PATCH', { status: 'delivered' })).status).toBe(200);
    expect(await status(id)).toBe('delivered');
    const attack = await request(`/api/messages/${id}`, 'PATCH', { status: 'replied' });
    expect(attack.status).toBeGreaterThanOrEqual(400);
    expect(await status(id)).toBe('delivered');
    expect(await replies(id)).toEqual([]);
  });

  it.each(['duplicate', 'expired'])('F16 boss-agent inbox rejects %s option answers', async (scenario) => {
    const key = fresh('f16-key');
    const actor = fresh('f16-actor');
    const boss = fresh('f16-boss');
    await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(actor, actor, await hashApiKey(key)).run();
    await env.DB.prepare("INSERT INTO bosses (id, name, role, agent_id) VALUES (?, ?, 'manager', ?)")
      .bind(boss, boss, actor).run();
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(boss, agent).run();
    const headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
    const control = fresh(`f16-${scenario}-control`);
    const target = fresh(`f16-${scenario}-target`);
    await ask(control, ['Yes', 'No']);
    await ask(target, ['Yes', 'No']);
    if (scenario === 'duplicate') {
      expect((await request(`/api/boss/messages/${control}/reply`, 'POST', { body: 'Yes' }, bossHeaders)).status).toBe(201);
      expect((await request(`/api/boss/messages/${control}/reply`, 'POST', { body: 'No' }, bossHeaders)).status).toBe(409);
      expect((await request(`/api/boss/inbox/${target}/reply`, 'POST', { body: 'Yes' }, headers)).status).toBe(201);
      expect(await replies(target)).toHaveLength(1);
    } else {
      await env.DB.prepare("UPDATE messages SET expires_at = datetime('now', '-1 minute') WHERE id IN (?, ?)")
        .bind(control, target).run();
      expect((await request(`/api/boss/messages/${control}/reply`, 'POST', { body: 'Yes' }, bossHeaders)).status).toBe(409);
      expect(await replies(control)).toEqual([]);
    }
    const rejected = await request(`/api/boss/inbox/${target}/reply`, 'POST', { body: 'No' }, headers);
    expect(rejected.status).toBeGreaterThanOrEqual(400);
    expect(await replies(target)).toHaveLength(scenario === 'duplicate' ? 1 : 0);
  });

  it.each(['boss-api', 'boss-inbox'])('F17 %s status patch cannot reopen a replied ask', async (route) => {
    const id = fresh(`f17-${route}`);
    await ask(id, ['Yes', 'No']);
    expect((await request(`/api/boss/messages/${id}/reply`, 'POST', { body: 'Yes' }, bossHeaders)).status).toBe(201);
    expect(await status(id)).toBe('replied');
    let path = `/api/boss/messages/${id}`;
    let headers = bossHeaders;
    if (route === 'boss-inbox') {
      const actor = fresh('f17-actor');
      const key = fresh('f17-key');
      const boss = fresh('f17-boss');
      await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
        .bind(actor, actor, await hashApiKey(key)).run();
      await env.DB.prepare("INSERT INTO bosses (id, name, role, agent_id) VALUES (?, ?, 'manager', ?)")
        .bind(boss, boss, actor).run();
      await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, agent).run();
      path = `/api/boss/inbox/${id}`;
      headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
    }
    const reopen = await request(path, 'PATCH', { status: 'delivered' }, headers);
    expect(reopen.status).toBeGreaterThanOrEqual(400);
    expect(await status(id)).toBe('replied');
    expect((await request(`/api/boss/messages/${id}/reply`, 'POST', { body: 'No' }, bossHeaders)).status).toBe(409);
    expect(await replies(id)).toHaveLength(1);
  });

  it('F18 failed reply insert cannot leave an option claimed', async () => {
    const control = fresh('f18-control');
    const target = fresh('f18-target');
    await ask(control, ['Yes']);
    await ask(target, ['Yes']);
    expect((await request(`/api/boss/messages/${control}/reply`, 'POST', { body: 'Yes' }, bossHeaders)).status).toBe(201);
    expect(await replies(control)).toHaveLength(1);
    const trigger = `fail_${crypto.randomUUID().replaceAll('-', '')}`;
    await env.DB.prepare(`CREATE TRIGGER ${trigger} BEFORE INSERT ON messages
      WHEN NEW.reply_to = '${target}' BEGIN SELECT RAISE(IGNORE); END`).run();
    try {
      const failed = await request(`/api/boss/messages/${target}/reply`, 'POST', { body: 'Yes' }, bossHeaders);
      expect(failed.status).toBeGreaterThanOrEqual(500);
      expect(await replies(target)).toEqual([]);
      expect(await status(target)).toBe('sent');
    } finally {
      await env.DB.prepare(`DROP TRIGGER ${trigger}`).run();
    }
  });

  it('F21 stale no-default expiry cannot overwrite an accepted answer', async () => {
    const control = fresh('f21-control');
    const target = fresh('f21-target');
    const pending = await ask(control, ['Yes']);
    const stale = await ask(target, ['Yes']);
    await expireMessageOptions(env as Env, agent, pending);
    expect(await status(control)).toBe('expired');
    expect((await request(`/api/boss/messages/${target}/reply`, 'POST', { body: 'Yes' }, bossHeaders)).status).toBe(201);
    expect(await replies(target)).toEqual([{ body: 'Yes', direction: 'boss_to_agent' }]);
    await expireMessageOptions(env as Env, agent, stale);
    expect(await status(target)).toBe('replied');
    expect(await replies(target)).toHaveLength(1);
  });
});
