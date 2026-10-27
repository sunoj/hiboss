// Shared synthetic messages, explicit APNs audience seeds and ephemeral signing keys.
// Exports notification fixtures; keeps unrelated environment bindings absent.

import { env } from 'cloudflare:test';
import { it, expect, type Mock } from 'vitest';
import { apnsEnv as resolutionApnsEnv, liveTokenId } from '../push/resolution-test-support';
import type { Env, MessageRow } from '../types';

export const fakeMessage: MessageRow = {
  id: 'msg-test-001',
  agent_id: 'test-agent-id',
  direction: 'boss_to_agent',
  mode: 'async',
  channel: 'telegram',
  body: 'Test callback message',
  status: 'sent',
  reply_to: null,
  priority: 'normal',
  type: null,
  target_agent_id: null,
  target_session_id: null,
  session_id: null,
  idempotency_key: null,
  metadata: null,
  created_at: '2026-03-16T00:00:00Z',
  updated_at: '2026-03-16T00:00:00Z',
};

export function bossCase(name: string, run: () => void | Promise<void>): void {
  it(`notifyBossAgents ${name}`, run);
}

export async function seedPushAgent(id: string, name: string, keyHash: string): Promise<void> {
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(id, name, keyHash).run();
}

export async function seedPushBoss(
  bossId: string, name: string, agentId: string, deviceToken: string, preferences?: string,
): Promise<void> {
  if (preferences === undefined) {
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role) VALUES (?, ?, ?)')
      .bind(bossId, name, 'manager').run();
  } else {
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)')
      .bind(bossId, name, 'manager', preferences).run();
  }
  await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, agentId).run();
  await env.DB.prepare(
    'INSERT OR REPLACE INTO boss_devices ' +
    '(boss_id, device_token, bundle_id, environment, platform, token_id) VALUES (?, ?, ?, ?, ?, ?)'
  ).bind(bossId, deviceToken, 'com.hiboss.ios', 'sandbox', 'ios', await liveTokenId(bossId)).run();
}

export async function apnsEnv(): Promise<Env> {
  const { APNS_AUTH_KEY } = await resolutionApnsEnv();
  return {
    DB: env.DB,
    ATTACHMENTS: undefined as never,
    APNS_KEY_ID: 'KEY1234567',
    APNS_TEAM_ID: 'TEAM123456',
    APNS_AUTH_KEY,
  };
}

type CapturedPush = Record<string, unknown> & {
  aps: Record<string, unknown> & { alert: Record<string, unknown> };
};

export function capturedPush(
  fetchMock: Mock<typeof fetch>, deviceToken: string,
): { init: RequestInit | undefined; payload: CapturedPush } {
  const call = fetchMock.mock.calls.find(([url]) => String(url).includes(deviceToken));
  expect(call).toBeDefined();
  if (!call) throw new Error(`Missing APNs fetch call for ${deviceToken}`);
  const init = call[1];
  return { init, payload: JSON.parse(String(init?.body)) as CapturedPush };
}
