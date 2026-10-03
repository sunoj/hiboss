// Signed Discord join-button integration cases for admin and viewer identities.
// Covers join approval status and rejection of a viewer's approval attempt.
// Depends on Cloudflare SELF, D1 fixtures, and Ed25519 Web Crypto signatures.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { getTestAgentId, seedDatabase } from '../test-helpers';

const endpoint = 'https://test.local/api/webhooks/discord-interactions';
const channel = 'discord-join-interactions-channel';
let privateKey: CryptoKey;

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare("INSERT OR IGNORE INTO channel_configs (agent_id, channel, config) VALUES (?, 'discord', ?)")
    .bind(getTestAgentId(), JSON.stringify({ channel_id: channel, bot_token: 'fake-token' })).run();
  const keys = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  privateKey = keys.privateKey;
  env.DISCORD_PUBLIC_KEY = hex(await crypto.subtle.exportKey('raw', keys.publicKey));
});

async function insertPending(requestId: string, name: string): Promise<void> {
  await env.DB.prepare(`INSERT INTO join_requests (id, poll_token_hash, status, device_label, profiles)
    VALUES (?, ?, 'pending', ?, ?)`)
    .bind(requestId, `hash-${requestId}`, `${name}-device`, JSON.stringify([{ profile: 'claude', name }])).run();
}

function hex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), byte => byte.toString(16).padStart(2, '0')).join('');
}

async function press(requestId: string, userId: string, content: string): Promise<Response> {
  const body = JSON.stringify({ type: 3, channel_id: channel, member: { user: { id: userId } },
    data: { custom_id: `join:approve:${requestId}` }, message: { content } });
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = hex(await crypto.subtle.sign('Ed25519', privateKey, new TextEncoder().encode(timestamp + body)));
  return SELF.fetch(endpoint, { method: 'POST', body,
    headers: { 'Content-Type': 'application/json', 'X-Signature-Timestamp': timestamp,
      'X-Signature-Ed25519': signature } });
}

it('approves a join request from a Discord button callback', async () => {
  const requestId = 'a077e0fa00000001aabbccdd00000001';
  await env.DB.prepare("INSERT INTO bosses (id, name, role, discord_user_id) VALUES ('discord-join-admin', 'Discord Join Admin', 'admin', 'discord-join-admin-user')").run();
  await insertPending(requestId, 'discord-join-test');
  const response = await press(requestId, 'discord-join-admin-user', 'Join request for discord-join-test');
  expect(response.status).toBe(200);
  const data = await response.json() as { type: number; data?: { content?: string; components?: unknown[] } };
  expect(data.type).toBe(7);
  expect(data.data?.content).toContain('Join request for discord-join-test');
  expect(data.data?.content).toContain('✅ Approved');
  expect(data.data?.components).toEqual([]);
  const approved = await env.DB.prepare('SELECT status, device_id, delivery FROM join_requests WHERE id = ?')
    .bind(requestId).first<{ status: string; device_id: string | null; delivery: string | null }>();
  expect(approved?.status).toBe('approved');
  expect(approved?.device_id).toBeTruthy();
  expect(approved?.delivery).toContain('"key":"hb_');
  const agent = await env.DB.prepare('SELECT device_id FROM api_keys WHERE name = ?').bind('discord-join-test').first('device_id');
  expect(agent).toBe(approved?.device_id);
  expect(await env.DB.prepare('SELECT boss_id FROM boss_agent_access ba JOIN api_keys a ON a.id = ba.agent_id WHERE a.name = ?')
    .bind('discord-join-test').first('boss_id')).toBe('discord-join-admin');
});

it('rejects join approvals from non-admin discord bosses', async () => {
  const requestId = 'a077e0fa00000009aabbccdd00000009';
  await insertPending(requestId, 'discord-join-viewer');
  await env.DB.prepare("INSERT INTO bosses (id, name, role, discord_user_id) VALUES ('discord-viewer-boss', 'Discord Viewer', 'viewer', 'discord-viewer-user')").run();
  const response = await press(requestId, 'discord-viewer-user', 'Join request for discord-join-viewer');
  expect(response.status).toBe(403);
  expect(await response.text()).toBe('admin required');
  const pending = await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?')
    .bind(requestId).first<{ status: string }>();
  expect(pending?.status).toBe('pending');
});
