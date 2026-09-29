// Regression probes for boss grants, viewer roles, and project lifecycle.
// Exercises public Worker routes with isolated D1 fixtures.
// Depends on Cloudflare SELF, shared seeding, agent keys, and Web Crypto.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it, vi } from 'vitest';
import { createAgent } from '../agent-keys';
import { seedBossToken, seedDatabase } from '../test-helpers';

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS join_requests (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, poll_token TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'pending', api_key_id TEXT REFERENCES api_keys(id),
    api_key TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  )`).run();
});
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

async function join(id: string): Promise<void> {
  await env.DB.prepare("INSERT INTO join_requests (id, name, poll_token, status) VALUES (?, ?, ?, 'pending')")
    .bind(id, `audit-${id}`, `poll-${id}`).run();
}

async function joinStatus(id: string): Promise<string | null> {
  const row = await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?')
    .bind(id).first<{ status: string }>();
  return row?.status ?? null;
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), byte => byte.toString(16).padStart(2, '0')).join('');
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

  it('F11 viewer associated agent cannot PATCH inbox status', async () => {
    const manager = await agent('audit-f11-manager-agent');
    const viewer = await agent('audit-f11-viewer-agent');
    const sub = await agent('audit-f11-sub-agent');
    for (const [id, role, associated] of [
      ['audit-f11-manager', 'manager', manager.id],
      ['audit-f11-viewer', 'viewer', viewer.id],
    ]) {
      await env.DB.prepare('INSERT INTO bosses (id, name, role, agent_id) VALUES (?, ?, ?, ?)')
        .bind(id, id, role, associated).run();
      await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
        .bind(id, sub.id).run();
    }
    await env.DB.prepare("INSERT INTO messages (id, agent_id, direction, mode, body, status) VALUES (?, ?, 'agent_to_boss', 'async', 'control', 'sent'), (?, ?, 'agent_to_boss', 'async', 'viewer attempt', 'sent')")
      .bind('audit-f11-control', sub.id, 'audit-f11-target', sub.id).run();
    const patch = (id: string, key: string): Promise<Response> => SELF.fetch(`${base}/api/boss/inbox/${id}`, {
      method: 'PATCH', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'read' }),
    });
    expect((await patch('audit-f11-control', manager.key)).status).toBe(200);
    expect(await env.DB.prepare("SELECT status FROM messages WHERE id = 'audit-f11-control'").first()).toEqual({ status: 'read' });
    expect(await env.DB.prepare("SELECT status FROM messages WHERE id = 'audit-f11-target'").first()).toEqual({ status: 'sent' });
    const attempt = await patch('audit-f11-target', viewer.key);
    expect(attempt.status).toBe(403);
    expect(await env.DB.prepare("SELECT status FROM messages WHERE id = 'audit-f11-target'").first()).toEqual({ status: 'sent' });
  });

  it('F15 Telegram viewer cannot reject a join request by button', async () => {
    const channelAgent = await agent('audit-f15-tg-agent');
    await env.DB.prepare("INSERT INTO channel_configs (agent_id, channel, config) VALUES (?, 'telegram', ?)")
      .bind(channelAgent.id, JSON.stringify({ chat_id: 'audit-f15-tg-chat', bot_token: 'audit-f15-bot' })).run();
    await env.DB.prepare("INSERT INTO bosses (id, name, role, telegram_user_id) VALUES ('audit-f15-tg-admin', 'admin', 'admin', 'audit-f15-tg-admin-user'), ('audit-f15-tg-viewer', 'viewer', 'viewer', 'audit-f15-tg-viewer-user')").run();
    const controlId = 'f1500000000000000000000000000001';
    const targetId = 'f1500000000000000000000000000002';
    await join(controlId);
    await join(targetId);
    const oldSecret = env.TELEGRAM_WEBHOOK_SECRET;
    env.TELEGRAM_WEBHOOK_SECRET = 'audit-f15-tg-secret';
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":true}', { status: 200 })));
    try {
      const press = (id: string, user: string): Promise<Response> => SELF.fetch(`${base}/api/webhooks/telegram`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Telegram-Bot-Api-Secret-Token': 'audit-f15-tg-secret' },
        body: JSON.stringify({ callback_query: { id: `callback-${id}`, data: `join:reject:${id}`, from: { id: user },
          message: { message_id: 1, text: 'Join request', chat: { id: 'audit-f15-tg-chat' } } } }),
      });
      expect((await press(controlId, 'audit-f15-tg-admin-user')).status).toBe(200);
      expect(await joinStatus(controlId)).toBe('rejected');
      expect(await joinStatus(targetId)).toBe('pending');
      await press(targetId, 'audit-f15-tg-viewer-user');
      expect(await joinStatus(targetId)).toBe('pending');
    } finally {
      env.TELEGRAM_WEBHOOK_SECRET = oldSecret;
      vi.unstubAllGlobals();
    }
  });

  it('F15 Discord viewer cannot reject a join request by button', async () => {
    const channelAgent = await agent('audit-f15-discord-agent');
    await env.DB.prepare("INSERT INTO channel_configs (agent_id, channel, config) VALUES (?, 'discord', ?)")
      .bind(channelAgent.id, JSON.stringify({ channel_id: 'audit-f15-discord-channel', bot_token: 'audit-f15-bot' })).run();
    await env.DB.prepare("INSERT INTO bosses (id, name, role, discord_user_id) VALUES ('audit-f15-discord-admin', 'admin', 'admin', 'audit-f15-discord-admin-user'), ('audit-f15-discord-viewer', 'viewer', 'viewer', 'audit-f15-discord-viewer-user')").run();
    const controlId = 'f1500000000000000000000000000003';
    const targetId = 'f1500000000000000000000000000004';
    await join(controlId);
    await join(targetId);
    const oldKey = env.DISCORD_PUBLIC_KEY;
    const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
    env.DISCORD_PUBLIC_KEY = hex(await crypto.subtle.exportKey('raw', keys.publicKey));
    try {
      const press = async (id: string, user: string): Promise<Response> => {
        const body = JSON.stringify({ type: 3, channel_id: 'audit-f15-discord-channel',
          data: { custom_id: `join:reject:${id}` }, member: { user: { id: user } }, message: { content: 'Join request' } });
        const timestamp = String(Math.floor(Date.now() / 1000));
        const signature = hex(await crypto.subtle.sign('Ed25519', keys.privateKey, new TextEncoder().encode(timestamp + body)));
        return SELF.fetch(`${base}/api/webhooks/discord-interactions`, { method: 'POST', body,
          headers: { 'Content-Type': 'application/json', 'X-Signature-Timestamp': timestamp, 'X-Signature-Ed25519': signature } });
      };
      expect((await press(controlId, 'audit-f15-discord-admin-user')).status).toBe(200);
      expect(await joinStatus(controlId)).toBe('rejected');
      expect(await joinStatus(targetId)).toBe('pending');
      await press(targetId, 'audit-f15-discord-viewer-user');
      expect(await joinStatus(targetId)).toBe('pending');
    } finally {
      env.DISCORD_PUBLIC_KEY = oldKey;
    }
  });
});
