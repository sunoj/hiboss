// Regression probes for viewer writes through agent inbox and channel buttons.
// Exercises public Worker routes with isolated D1 fixtures and signed webhooks.
// Depends on Cloudflare SELF, shared database seeding, and Web Crypto.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it, vi } from 'vitest';
import { createAgent } from '../agent-keys';
import { seedDatabase } from '../test-helpers';

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

describe('Business audit viewer boundaries', () => {
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
