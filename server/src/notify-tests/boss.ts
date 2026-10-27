// Boss device notifications, privacy, preference and token-pruning contracts.
// Registers six populated notification scenarios with the root database hooks.

import { env } from 'cloudflare:test';
import { expect, vi } from 'vitest';
import { notifyBossAgents } from '../notify';
import { fakeMessage, seedPushAgent, seedPushBoss, apnsEnv, bossCase, capturedPush } from './support';

bossCase('sends APNs payloads to boss devices and prunes bad tokens', async () => {
  const agentId = 'notify-apns-agent';
  const bossId = 'notify-apns-boss';
  const deviceToken = 'deadbeef1234';
  const sessionId = 'notify-apns-session';
  await seedPushAgent(agentId, 'Push Agent', 'notify-apns-key-hash');
  await env.DB.prepare('INSERT OR REPLACE INTO sessions (id, agent_id, label, branch) VALUES (?, ?, ?, ?)')
    .bind(sessionId, agentId, 'hiboss/feat-notif', 'feat/notif')
    .run();
  await seedPushBoss(bossId, 'Push Boss', agentId, deviceToken);
  const fetchMock = vi.fn<typeof fetch>(
    async () => Response.json({ reason: 'BadDeviceToken' }, { status: 400 }),
  );
  vi.stubGlobal('fetch', fetchMock);

  await notifyBossAgents(await apnsEnv(), agentId, {
    ...fakeMessage,
    id: 'notify-apns-message',
    agent_id: agentId,
    direction: 'agent_to_boss',
    body: 'x'.repeat(180),
    priority: 'high',
    session_id: sessionId,
    metadata: JSON.stringify({ content: 'Deploy approval', options: ['Approve', 'Reject'] }),
  });

  const { init, payload: sentPayload } = capturedPush(fetchMock, deviceToken);
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

bossCase('uses the agent title and unprefixed body when no session is present', async () => {
  const agentId = 'notify-no-session-agent';
  const bossId = 'notify-no-session-boss';
  const deviceToken = 'nosessiondeadbeef';
  await seedPushAgent(agentId, 'No Session Agent', 'notify-no-session-key-hash');
  await seedPushBoss(bossId, 'No Session Boss', agentId, deviceToken);
  const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
  vi.stubGlobal('fetch', fetchMock);

  await notifyBossAgents(await apnsEnv(), agentId, {
    ...fakeMessage,
    id: 'notify-no-session-message',
    agent_id: agentId,
    direction: 'agent_to_boss',
    body: 'Ready to deploy',
    priority: 'high',
  });

  const { payload: sentPayload } = capturedPush(fetchMock, deviceToken);
  expect(sentPayload.aps.alert.title).toBe('No Session Agent');
  expect(sentPayload.aps.alert.body).toBe('Ready to deploy');
});

bossCase('keeps private push payloads generic even with session content', async () => {
  const agentId = 'notify-private-agent';
  const bossId = 'notify-private-boss';
  const deviceToken = 'privatedeadbeef';
  const sessionId = 'notify-private-session';
  await seedPushAgent(agentId, 'Private Agent', 'notify-private-key-hash');
  await env.DB.prepare('INSERT OR REPLACE INTO sessions (id, agent_id, label, branch) VALUES (?, ?, ?, ?)')
    .bind(sessionId, agentId, 'private/project', 'main')
    .run();
  await seedPushBoss(bossId, 'Private Boss', agentId, deviceToken, JSON.stringify({ private_push: true }));
  const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
  vi.stubGlobal('fetch', fetchMock);

  await notifyBossAgents(await apnsEnv(), agentId, {
    ...fakeMessage,
    id: 'notify-private-message',
    agent_id: agentId,
    direction: 'agent_to_boss',
    body: 'Sensitive body',
    priority: 'high',
    session_id: sessionId,
    metadata: JSON.stringify({ content: 'Sensitive context', options: ['Approve'] }),
  });

  const { payload: sentPayload } = capturedPush(fetchMock, deviceToken);
  expect(sentPayload.aps.alert.title).toBe('HiBoss');
  expect(sentPayload.aps.alert.subtitle).toBeUndefined();
  expect(sentPayload.aps.alert.body).toBe('New decision from Private Agent');
  expect(sentPayload.options).toBeUndefined();
});

bossCase('suppresses normal status pushes when a boss preference disables delivery', async () => {
  const agentId = 'notify-pref-agent';
  const bossId = 'notify-pref-boss';
  const deviceToken = 'prefdeadbeef1234';
  await seedPushAgent(agentId, 'Preference Agent', 'notify-pref-key-hash');
  await seedPushBoss(bossId, 'Preference Boss',
    agentId, deviceToken, JSON.stringify({ push: { normal: { deliver: false } } }));
  const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
  vi.stubGlobal('fetch', fetchMock);

  await notifyBossAgents(await apnsEnv(), agentId, {
    ...fakeMessage,
    id: 'notify-pref-status',
    agent_id: agentId,
    direction: 'agent_to_boss',
    priority: 'normal',
    metadata: null,
  });

  expect(fetchMock.mock.calls.some(([url]) => String(url).includes(deviceToken))).toBe(false);
});

bossCase('delivers decision pushes even when a boss preference disables the priority', async () => {
  const agentId = 'notify-decision-pref-agent';
  const bossId = 'notify-decision-pref-boss';
  const deviceToken = 'decisionprefdeadbeef';
  await seedPushAgent(agentId, 'Decision Preference Agent', 'notify-decision-pref-key-hash');
  await seedPushBoss(bossId, 'Decision Preference Boss',
    agentId, deviceToken, JSON.stringify({ push: { normal: { deliver: false } } }));
  const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
  vi.stubGlobal('fetch', fetchMock);

  await notifyBossAgents(await apnsEnv(), agentId, {
    ...fakeMessage,
    id: 'notify-pref-decision',
    agent_id: agentId,
    direction: 'agent_to_boss',
    priority: 'normal',
    metadata: JSON.stringify({ options: ['Approve', 'Wait'] }),
  });

  const { init, payload: sentPayload } = capturedPush(fetchMock, deviceToken);
  expect(sentPayload.aps.sound).toBe('default');
  expect(sentPayload.aps['interruption-level']).toBe('active');
});

bossCase('lets normal decisions follow status tiering when decision alerts are disabled', async () => {
  const agentId = 'notify-decision-alerts-off-agent';
  const bossId = 'notify-decision-alerts-off-boss';
  const deviceToken = 'decisionalertsoffdeadbeef';
  await seedPushAgent(agentId, 'Decision Alerts Off Agent', 'notify-decision-alerts-off-key-hash');
  await seedPushBoss(bossId, 'Decision Alerts Off Boss',
    agentId, deviceToken, JSON.stringify({ decision_alerts: false }));
  const fetchMock = vi.fn<typeof fetch>(async () => Response.json({}, { status: 200 }));
  vi.stubGlobal('fetch', fetchMock);

  await notifyBossAgents(await apnsEnv(), agentId, {
    ...fakeMessage,
    id: 'notify-decision-alerts-off',
    agent_id: agentId,
    direction: 'agent_to_boss',
    priority: 'normal',
    metadata: JSON.stringify({ options: ['Approve', 'Wait'] }),
  });

  const { init, payload: sentPayload } = capturedPush(fetchMock, deviceToken);
  expect(sentPayload.aps.sound).toBeUndefined();
  expect(sentPayload.aps['interruption-level']).toBe('passive');
  expect((init?.headers as Record<string, string>)['apns-priority']).toBe('5');
  expect(sentPayload.aps.category).toBe('HIBOSS_OPTIONS');
  expect(sentPayload.category).toBe('HIBOSS_OPTIONS');
  expect(sentPayload.options).toEqual(['Approve', 'Wait']);
});
