// Regression probes for boss grant boundaries in routing and project lifecycle.
// Exercises public Worker routes with isolated D1 fixtures.
// Depends on Cloudflare SELF, shared database seeding, and agent key creation.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { createAgent } from '../agent-keys';
import { seedBossToken, seedDatabase } from '../test-helpers';

beforeAll(seedDatabase);
const base = 'https://test.local';

async function agent(name: string): Promise<{ id: string; key: string }> {
  const created = await createAgent(env.DB, name, { type: 'system', id: 'business-audit' });
  if (!created) throw new Error(`failed to create ${name}`);
  return created;
}

async function project(id: string, owner: string): Promise<void> {
  await env.DB.prepare('INSERT INTO projects (id, slug, display_name, created_by_agent_id) VALUES (?, ?, ?, ?)')
    .bind(id, id, id, owner).run();
  await env.DB.prepare("INSERT INTO project_aliases (alias, project_id, source) VALUES (?, ?, 'explicit')")
    .bind(id, id).run();
}

async function session(id: string, owner: string, projectId: string): Promise<void> {
  await env.DB.prepare('INSERT INTO sessions (id, agent_id, project_id) VALUES (?, ?, ?)')
    .bind(id, owner, projectId).run();
}

async function sessionProject(id: string): Promise<string | null> {
  const row = await env.DB.prepare('SELECT project_id FROM sessions WHERE id = ?')
    .bind(id).first<{ project_id: string | null }>();
  return row?.project_id ?? null;
}

describe('Business audit access boundaries', () => {
  it('F5 Telegram rule cannot retarget a boss message to an ungranted agent', async () => {
    const allowed = await agent('audit-f5-allowed');
    const hidden = await agent('audit-f5-hidden');
    const boss = await seedBossToken('audit-f5-boss', 'manager', 'audit-f5-token');
    await env.DB.prepare('UPDATE bosses SET telegram_user_id = ? WHERE id = ?').bind('audit-f5-user', boss).run();
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, allowed.id).run();
    await env.DB.prepare("INSERT INTO channel_configs (agent_id, channel, config) VALUES (?, 'telegram', ?)")
      .bind(allowed.id, JSON.stringify({ chat_id: 'audit-f5-chat', bot_token: 'audit-f5-bot' })).run();
    await env.DB.prepare("INSERT INTO routing_rules (owner_id, channel, pattern, target_agent_id) VALUES (?, 'telegram', ?, ?)")
      .bind(allowed.id, 'secret-route', hidden.id).run();
    const oldSecret = env.TELEGRAM_WEBHOOK_SECRET;
    env.TELEGRAM_WEBHOOK_SECRET = 'audit-f5-webhook';
    try {
      const send = (text: string): Promise<Response> => SELF.fetch(`${base}/api/webhooks/telegram`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': 'audit-f5-webhook' },
        body: JSON.stringify({ message: { chat: { id: 'audit-f5-chat' }, from: { id: 'audit-f5-user' }, text } }),
      });
      const control = await send('ordinary message');
      expect(control.status).toBe(201);
      expect(await control.json()).toMatchObject({ agent_id: allowed.id });
      expect(await env.DB.prepare('SELECT 1 AS present FROM boss_agent_access WHERE boss_id = ? AND agent_id = ?')
        .bind(boss, hidden.id).first()).toBeNull();
      await send('secret-route');
      expect(await env.DB.prepare("SELECT COUNT(*) AS count FROM messages WHERE body = 'secret-route' AND agent_id = ?")
        .bind(hidden.id).first()).toEqual({ count: 0 });
    } finally {
      env.TELEGRAM_WEBHOOK_SECRET = oldSecret;
    }
  });

  it('F3 boss merge preserves sessions of agents outside its grants', async () => {
    const allowed = await agent('audit-f3-allowed');
    const hidden = await agent('audit-f3-hidden');
    const token = 'audit-f3-boss-token';
    const boss = await seedBossToken('audit-f3-boss', 'manager', token);
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, allowed.id).run();
    for (const id of ['audit-f3-good-from', 'audit-f3-good-to', 'audit-f3-mixed-from', 'audit-f3-mixed-to']) {
      await project(id, allowed.id);
    }
    await session('audit-f3-good-session', allowed.id, 'audit-f3-good-from');
    await session('audit-f3-allowed-session', allowed.id, 'audit-f3-mixed-from');
    await session('audit-f3-hidden-session', hidden.id, 'audit-f3-mixed-from');
    await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, target, label) VALUES (?, ?, 'telegram_chat', '{}', 'audit route')")
      .bind('audit-f3-destination', boss).run();
    await env.DB.prepare('INSERT INTO destination_routes (id, destination_id, session_id, project_id) VALUES (?, ?, ?, ?), (?, ?, ?, ?)')
      .bind('audit-f3-good-route', 'audit-f3-destination', 'audit-f3-good-session', 'audit-f3-good-from',
        'audit-f3-hidden-route', 'audit-f3-destination', 'audit-f3-hidden-session', 'audit-f3-mixed-from').run();
    const merge = (from: string, into: string): Promise<Response> => SELF.fetch(`${base}/api/boss/projects/${from}`, {
      method: 'PATCH', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ merge_into: into }),
    });
    expect((await merge('audit-f3-good-from', 'audit-f3-good-to')).status).toBe(200);
    expect(await sessionProject('audit-f3-good-session')).toBe('audit-f3-good-to');
    expect(await env.DB.prepare("SELECT project_id FROM destination_routes WHERE id = 'audit-f3-good-route'").first())
      .toEqual({ project_id: 'audit-f3-good-to' });
    expect(await sessionProject('audit-f3-hidden-session')).toBe('audit-f3-mixed-from');
    await merge('audit-f3-mixed-from', 'audit-f3-mixed-to');
    expect(await sessionProject('audit-f3-hidden-session')).toBe('audit-f3-mixed-from');
    expect(await env.DB.prepare("SELECT project_id FROM destination_routes WHERE id = 'audit-f3-hidden-route'").first())
      .toEqual({ project_id: 'audit-f3-mixed-from' });
  });

  it('F2 agent progress aliases cannot merge away a project containing another agent session', async () => {
    const caller = await agent('audit-f2-caller');
    const hidden = await agent('audit-f2-hidden');
    await project('audit-f2-winner', caller.id);
    await project('audit-f2-other', hidden.id);
    await session('audit-f2-other-session', hidden.id, 'audit-f2-other');
    const post = (projectIdentity: { slug: string; aliases: string[] }, body: string): Promise<Response> =>
      SELF.fetch(`${base}/api/progress`, {
        method: 'POST', headers: { Authorization: `Bearer ${caller.key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ body, project: projectIdentity }),
      });
    const control = await post({ slug: 'audit-f2-winner', aliases: [] }, 'control progress');
    expect(control.status).toBe(201);
    expect(await control.json()).toMatchObject({ project_ref: { id: 'audit-f2-winner' } });
    expect(await sessionProject('audit-f2-other-session')).toBe('audit-f2-other');
    await post({ slug: 'audit-f2-winner', aliases: ['audit-f2-other'] }, 'alias collision');
    expect(await sessionProject('audit-f2-other-session')).toBe('audit-f2-other');
    expect(await env.DB.prepare("SELECT id FROM projects WHERE id = 'audit-f2-other'").first()).toEqual({ id: 'audit-f2-other' });
  });
});
