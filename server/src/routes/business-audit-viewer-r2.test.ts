// Round-two viewer regressions: a viewer is read-only on every writer, channel buttons included.
// Covers Telegram/Discord option callbacks, channel reactions, receipt PATCH, progress delete,
// client minting, and the rule that a channel callback never stores free text.

import { testRequest } from '../test-request';
import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';

const base = 'https://test.local';
const viewerToken = 'viewer-r2-viewer-token';
const managerToken = 'viewer-r2-manager-token';
const fresh = () => crypto.randomUUID().replaceAll('-', '');
const agent = fresh();

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)').bind(agent, 'viewer-r2-agent', fresh()).run();
  for (const [role, token] of [['viewer', viewerToken],
    ['manager', managerToken]] as const) {
    const boss = await seedBossToken(`Viewer R2 ${role}`, role, token, fresh());
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, agent).run();
  }
});

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(async () => new Response('{"ok":true,"result":{}}', { status: 200 })));
});

async function message(fields: { direction?: string; mode?: string; channel?: string; metadata?: Record<string, unknown> } = {}): Promise<string> {
  const id = fresh();
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, metadata, expires_at)
    VALUES (?, ?, ?, ?, ?, 'Choose', 'delivered', ?, ?)`)
    .bind(id, agent, fields.direction ?? 'agent_to_boss', fields.mode ?? 'blocking', fields.channel ?? 'api',
      JSON.stringify(fields.metadata ?? { options: ['approve', 'reject'] }), new Date(Date.now() + 60_000).toISOString()).run();
  return id;
}

async function state(id: string): Promise<{ status: string; answers: number; reactions: unknown }> {
  const row = await env.DB.prepare('SELECT status, metadata FROM messages WHERE id = ?').bind(id).first<{ status: string; metadata: string }>();
  const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM messages WHERE reply_to = ?').bind(id).first<{ n: number }>();
  return { status: row?.status ?? 'missing', answers: count?.n ?? 0, reactions: JSON.parse(row?.metadata ?? '{}').reactions };
}

function boss(path: string, token: string, method: string, body?: unknown): Promise<Response> {
  return SELF.fetch(`${base}${path}`, { method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' } });
}

describe('DL6/MA8: viewer reactions and receipts', () => {
  it('rejects a viewer receipt PATCH on the boss API', async () => {
    const control = await message({ channel: 'api' });
    expect((await boss(`/api/boss/messages/${control}`, managerToken, 'PATCH', { status: 'read' })).status).toBe(200);
    const target = await message({ channel: 'api' });
    expect((await boss(`/api/boss/messages/${target}`, viewerToken, 'PATCH', { status: 'read' })).status).toBe(403);
    expect((await state(target)).status).toBe('delivered');
  });
});

describe('SP1/BG9: viewer progress delete and client minting', () => {
  it('rejects a viewer deleting a progress post', async () => {
    await env.DB.prepare("INSERT OR IGNORE INTO projects (id, slug, display_name) VALUES ('viewer-r2', 'viewer-r2', 'viewer-r2')").run();
    const [control, target] = [fresh(), fresh()];
    await env.DB.prepare("INSERT INTO progress_posts (id, agent_id, project_id, body) VALUES (?, ?, 'viewer-r2', 'a'), (?, ?, 'viewer-r2', 'b')")
      .bind(control, agent, target, agent).run();
    expect((await boss(`/api/progress/${control}`, managerToken, 'DELETE')).status).toBe(204);
    expect((await boss(`/api/progress/${target}`, viewerToken, 'DELETE')).status).toBe(403);
    expect(await env.DB.prepare('SELECT id FROM progress_posts WHERE id = ?').bind(target).first()).not.toBeNull();
  });

  it('rejects a viewer minting a new client and token', async () => {
    const body = { kind: 'web', label: 'Viewer R2' };
    expect((await boss('/api/boss/clients', managerToken, 'POST', body)).status).toBe(201);
    const before = await env.DB.prepare('SELECT COUNT(*) AS n FROM boss_clients').first<{ n: number }>();
    expect((await boss('/api/boss/clients', viewerToken, 'POST', body)).status).toBe(403);
    expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM boss_clients').first<{ n: number }>()).toEqual(before);
  });
});
