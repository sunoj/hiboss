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
    const sessionId = 'notify-apns-session';
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, 'Push Agent', 'notify-apns-key-hash')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO sessions (id, agent_id, label, branch) VALUES (?, ?, ?, ?)')
      .bind(sessionId, agentId, 'hiboss/feat-notif', 'feat/notif')
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
      session_id: sessionId,
      metadata: JSON.stringify({ content: 'Deploy approval', options: ['Approve', 'Reject'] }),
    });

    const call = fetchMock.mock.calls.find(([url]) => String(url).includes(deviceToken));
    expect(call).toBeDefined();
    if (!call) throw new Error('missing APNs fetch call');
    const init = call[1];
    const sentPayload = JSON.parse(String(init?.body)) as {
      aps: {
        alert: { title: string; subtitle?: string; body: string };
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
    expect(sentPayload.aps.alert.title).toBe('hiboss/feat-notif');
    expect(sentPayload.aps.alert.subtitle).toBe('Deploy approval');
    expect(sentPayload.aps.alert.body).toMatch(/^Push Agent · /);
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

  it('uses the agent title and unprefixed body when no session is present', async () => {
    const agentId = 'notify-no-session-agent';
    const bossId = 'notify-no-session-boss';
    const deviceToken = 'nosessiondeadbeef';
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, 'No Session Agent', 'notify-no-session-key-hash')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role) VALUES (?, ?, ?)')
      .bind(bossId, 'No Session Boss', 'manager')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, agentId)
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_devices (boss_id, device_token, bundle_id, environment, platform) VALUES (?, ?, ?, ?, ?)')
      .bind(bossId, deviceToken, 'com.hiboss.ios', 'sandbox', 'ios')
      .run();
    const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await notifyBossAgents(apnsEnv(await createPrivateKeyPem()), agentId, {
      ...fakeMessage,
      id: 'notify-no-session-message',
      agent_id: agentId,
      direction: 'agent_to_boss',
      body: 'Ready to deploy',
      priority: 'high',
    });

    const call = fetchMock.mock.calls.find(([url]) => String(url).includes(deviceToken));
    expect(call).toBeDefined();
    if (!call) throw new Error('missing no-session APNs fetch call');
    const sentPayload = JSON.parse(String(call[1]?.body)) as { aps: { alert: { title: string; body: string } } };
    expect(sentPayload.aps.alert.title).toBe('No Session Agent');
    expect(sentPayload.aps.alert.body).toBe('Ready to deploy');
  });

  it('keeps private push payloads generic even with session content', async () => {
    const agentId = 'notify-private-agent';
    const bossId = 'notify-private-boss';
    const deviceToken = 'privatedeadbeef';
    const sessionId = 'notify-private-session';
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, 'Private Agent', 'notify-private-key-hash')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO sessions (id, agent_id, label, branch) VALUES (?, ?, ?, ?)')
      .bind(sessionId, agentId, 'private/project', 'main')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)')
      .bind(bossId, 'Private Boss', 'manager', JSON.stringify({ private_push: true }))
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, agentId)
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_devices (boss_id, device_token, bundle_id, environment, platform) VALUES (?, ?, ?, ?, ?)')
      .bind(bossId, deviceToken, 'com.hiboss.ios', 'sandbox', 'ios')
      .run();
    const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await notifyBossAgents(apnsEnv(await createPrivateKeyPem()), agentId, {
      ...fakeMessage,
      id: 'notify-private-message',
      agent_id: agentId,
      direction: 'agent_to_boss',
      body: 'Sensitive body',
      priority: 'high',
      session_id: sessionId,
      metadata: JSON.stringify({ content: 'Sensitive context', options: ['Approve'] }),
    });

    const call = fetchMock.mock.calls.find(([url]) => String(url).includes(deviceToken));
    expect(call).toBeDefined();
    if (!call) throw new Error('missing private APNs fetch call');
    const sentPayload = JSON.parse(String(call[1]?.body)) as { aps: { alert: { title: string; subtitle?: string; body: string } }; options?: string[] };
    expect(sentPayload.aps.alert.title).toBe('HiBoss');
    expect(sentPayload.aps.alert.subtitle).toBeUndefined();
    expect(sentPayload.aps.alert.body).toBe('New decision from Private Agent');
    expect(sentPayload.options).toBeUndefined();
  });

  it('suppresses normal status pushes when a boss preference disables delivery', async () => {
    const agentId = 'notify-pref-agent';
    const bossId = 'notify-pref-boss';
    const deviceToken = 'prefdeadbeef1234';
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, 'Preference Agent', 'notify-pref-key-hash')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)')
      .bind(bossId, 'Preference Boss', 'manager', JSON.stringify({ push: { normal: { deliver: false } } }))
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, agentId)
      .run();
    await env.DB.prepare(
      'INSERT OR REPLACE INTO boss_devices (boss_id, device_token, bundle_id, environment, platform) VALUES (?, ?, ?, ?, ?)'
    )
      .bind(bossId, deviceToken, 'com.hiboss.ios', 'sandbox', 'ios')
      .run();
    const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await notifyBossAgents(apnsEnv(await createPrivateKeyPem()), agentId, {
      ...fakeMessage,
      id: 'notify-pref-status',
      agent_id: agentId,
      direction: 'agent_to_boss',
      priority: 'normal',
      metadata: null,
    });

    expect(fetchMock.mock.calls.some(([url]) => String(url).includes(deviceToken))).toBe(false);
  });

  it('delivers decision pushes even when a boss preference disables the priority', async () => {
    const agentId = 'notify-decision-pref-agent';
    const bossId = 'notify-decision-pref-boss';
    const deviceToken = 'decisionprefdeadbeef';
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, 'Decision Preference Agent', 'notify-decision-pref-key-hash')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)')
      .bind(bossId, 'Decision Preference Boss', 'manager', JSON.stringify({ push: { normal: { deliver: false } } }))
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, agentId)
      .run();
    await env.DB.prepare(
      'INSERT OR REPLACE INTO boss_devices (boss_id, device_token, bundle_id, environment, platform) VALUES (?, ?, ?, ?, ?)'
    )
      .bind(bossId, deviceToken, 'com.hiboss.ios', 'sandbox', 'ios')
      .run();
    const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await notifyBossAgents(apnsEnv(await createPrivateKeyPem()), agentId, {
      ...fakeMessage,
      id: 'notify-pref-decision',
      agent_id: agentId,
      direction: 'agent_to_boss',
      priority: 'normal',
      metadata: JSON.stringify({ options: ['Approve', 'Wait'] }),
    });

    const call = fetchMock.mock.calls.find(([url]) => String(url).includes(deviceToken));
    expect(call).toBeDefined();
    if (!call) throw new Error('missing decision APNs fetch call');
    const init = call[1];
    const sentPayload = JSON.parse(String(init?.body)) as { aps: { sound?: string; 'interruption-level': string } };
    expect(sentPayload.aps.sound).toBe('default');
    expect(sentPayload.aps['interruption-level']).toBe('active');
  });

  it('lets normal decisions follow status tiering when decision alerts are disabled', async () => {
    const agentId = 'notify-decision-alerts-off-agent';
    const bossId = 'notify-decision-alerts-off-boss';
    const deviceToken = 'decisionalertsoffdeadbeef';
    await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
      .bind(agentId, 'Decision Alerts Off Agent', 'notify-decision-alerts-off-key-hash')
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO bosses (id, name, role, preferences) VALUES (?, ?, ?, ?)')
      .bind(bossId, 'Decision Alerts Off Boss', 'manager', JSON.stringify({ decision_alerts: false }))
      .run();
    await env.DB.prepare('INSERT OR REPLACE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
      .bind(bossId, agentId)
      .run();
    await env.DB.prepare(
      'INSERT OR REPLACE INTO boss_devices (boss_id, device_token, bundle_id, environment, platform) VALUES (?, ?, ?, ?, ?)'
    )
      .bind(bossId, deviceToken, 'com.hiboss.ios', 'sandbox', 'ios')
      .run();
    const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
    vi.stubGlobal('fetch', fetchMock);

    await notifyBossAgents(apnsEnv(await createPrivateKeyPem()), agentId, {
      ...fakeMessage,
      id: 'notify-decision-alerts-off',
      agent_id: agentId,
      direction: 'agent_to_boss',
      priority: 'normal',
      metadata: JSON.stringify({ options: ['Approve', 'Wait'] }),
    });

    const call = fetchMock.mock.calls.find(([url]) => String(url).includes(deviceToken));
    expect(call).toBeDefined();
    if (!call) throw new Error('missing decision APNs fetch call');
    const init = call[1];
    const sentPayload = JSON.parse(String(init?.body)) as {
      aps: { sound?: string; 'interruption-level': string; category: string };
      category: string;
      options: string[];
    };
    expect(sentPayload.aps.sound).toBeUndefined();
    expect(sentPayload.aps['interruption-level']).toBe('passive');
    expect((init?.headers as Record<string, string>)['apns-priority']).toBe('5');
    expect(sentPayload.aps.category).toBe('HIBOSS_OPTIONS');
    expect(sentPayload.category).toBe('HIBOSS_OPTIONS');
    expect(sentPayload.options).toEqual(['Approve', 'Wait']);
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
