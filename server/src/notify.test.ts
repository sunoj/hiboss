// Integration tests for agent and boss push notification paths.
// Tests callback delivery plus APNs payload and pruning behavior.
// Depends on cloudflare:test D1 and shared test helpers.

import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase, getTestAgentId } from './test-helpers';
import { notifyAgentCallback, notifyBossAgents } from './notify';
import type { Env, MessageRow } from './types';

const fakeMessage: MessageRow = {
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

beforeAll(async () => {
  await seedDatabase();
});

describe('notifyAgentCallback', () => {
  it('returns silently when agent has no callback_url set', async () => {
    const agentId = getTestAgentId();
    // Default seeded agent has no callback_url — should return without error
    await expect(
      notifyAgentCallback(env as never, agentId, fakeMessage),
    ).resolves.toBeUndefined();
  });

  it('returns silently when agent does not exist', async () => {
    await expect(
      notifyAgentCallback(env as never, 'nonexistent-agent-id', fakeMessage),
    ).resolves.toBeUndefined();
  });

  it('does not throw when callback fetch fails', async () => {
    const agentId = getTestAgentId();
    // Set a callback_url that will fail (unreachable host)
    await env.DB.prepare('UPDATE api_keys SET callback_url = ? WHERE id = ?')
      .bind('http://0.0.0.0:1/callback', agentId)
      .run();

    await expect(
      notifyAgentCallback(env as never, agentId, fakeMessage),
    ).resolves.toBeUndefined();

    // Clean up: remove callback_url so other tests aren't affected
    await env.DB.prepare('UPDATE api_keys SET callback_url = NULL WHERE id = ?')
      .bind(agentId)
      .run();
  });
});

describe('notifyBossAgents', () => {
  it('sends APNs payloads to boss devices and prunes bad tokens', async () => {
    const agentId = 'notify-apns-agent';
    const bossId = 'notify-apns-boss';
    const deviceToken = 'deadbeef1234';
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, 'Push Agent', 'notify-apns-key-hash')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role) VALUES (?, ?, ?)')
      .bind(bossId, 'Push Boss', 'manager')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, agentId)
      .run();
    await env.DB.prepare(
      'INSERT OR REPLACE INTO boss_devices (boss_id, device_token, bundle_id, environment, platform) VALUES (?, ?, ?, ?, ?)'
    )
      .bind(bossId, deviceToken, 'com.hiboss.ios', 'sandbox', 'ios')
      .run();
    const fetchMock = vi.fn<typeof fetch>(
      async () => Response.json({ reason: 'BadDeviceToken' }, { status: 400 }),
    );
    vi.stubGlobal('fetch', fetchMock);

    await notifyBossAgents(apnsEnv(await createPrivateKeyPem()), agentId, {
      ...fakeMessage,
      id: 'notify-apns-message',
      agent_id: agentId,
      direction: 'agent_to_boss',
      body: 'x'.repeat(180),
      priority: 'high',
      metadata: JSON.stringify({ options: ['Approve', 'Reject'] }),
    });

    const call = fetchMock.mock.calls.find(([url]) => String(url).includes(deviceToken));
    expect(call).toBeDefined();
    if (!call) throw new Error('missing APNs fetch call');
    const init = call[1];
    const sentPayload = JSON.parse(String(init?.body)) as {
      aps: {
        alert: { title: string; body: string };
        sound?: string;
        'interruption-level': string;
        'thread-id': string;
        category: string;
      };
      category: string;
      options: string[];
      agentName: string;
      priority: string;
      direction: string;
    };
    expect(sentPayload.aps.alert.title).toBe('Push Agent');
    expect(sentPayload.aps.alert.body).toHaveLength(150);
    // A high-priority decision (has options) alerts as 'active' with sound at prio 10.
    expect(sentPayload.aps['interruption-level']).toBe('active');
    expect(sentPayload.aps.sound).toBe('default');
    expect((init?.headers as Record<string, string>)['apns-priority']).toBe('10');
    expect(sentPayload.aps['thread-id']).toBe(bossId);
    // iOS reads the action category from aps.category, not the top-level key.
    expect(sentPayload.aps.category).toBe('HIBOSS_OPTIONS');
    expect(sentPayload.category).toBe('HIBOSS_OPTIONS');
    expect(sentPayload.options).toEqual(['Approve', 'Reject']);
    expect(sentPayload.agentName).toBe('Push Agent');
    expect(sentPayload.priority).toBe('high');
    expect(sentPayload.direction).toBe('agent_to_boss');

    const row = await env.DB.prepare('SELECT id FROM boss_devices WHERE device_token = ?')
      .bind(deviceToken)
      .first<{ id: string }>();
    expect(row).toBeNull();
  });
});

function apnsEnv(authKey: string): Env {
  return {
    DB: env.DB,
    ATTACHMENTS: undefined as never,
    APNS_KEY_ID: 'KEY1234567',
    APNS_TEAM_ID: 'TEAM123456',
    APNS_AUTH_KEY: authKey,
  };
}

async function createPrivateKeyPem(): Promise<string> {
  const pair = await crypto.subtle.generateKey(
    { name: 'ECDSA', namedCurve: 'P-256' },
    true,
    ['sign', 'verify'],
  );
  const pkcs8 = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  return `-----BEGIN PRIVATE KEY-----\n${base64Bytes(new Uint8Array(pkcs8))}\n-----END PRIVATE KEY-----`;
}

function base64Bytes(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}
