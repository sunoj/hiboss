// End-to-end admin visibility and explicit viewer grants through panel HTTP/relay.
// Exercises definition, lifecycle state, and subscriber tickets using real D1/DOs.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../test-helpers';

const ADMIN = 'panel-access-admin';
const VIEWER = 'panel-access-viewer';
const OTHER_ADMIN = 'panel-access-other-admin';
const url = 'https://test.local/api/panels';
const headers = (token: string): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Access Admin', 'admin', ADMIN, ADMIN);
  await seedBossToken('Other Admin', 'admin', OTHER_ADMIN, OTHER_ADMIN);
  await seedBossToken('Access Viewer', 'viewer', VIEWER, VIEWER);
  await env.DB.prepare("INSERT INTO sessions (id, agent_id, label) VALUES ('access-session', ?, 'access')").bind(getTestAgentId()).run();
});

async function publish(targetBossId = ADMIN): Promise<Response> {
  return SELF.fetch(url, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() }, body: JSON.stringify({
    protocolVersion: 2, targetBossId, sessionId: 'access-session', taskKey: 'access', title: 'Access', catalogId: 'hiboss.panel', catalogVersion: 1,
    spec: { root: 'metric', elements: { metric: { type: 'Metric', props: { label: 'Done', value: { $state: '/task/done' } }, children: [] } } },
    stateSchema: { type: 'object', properties: { task: { type: 'object', properties: { done: { type: 'integer' } }, required: ['done'], additionalProperties: false } }, required: ['task'], additionalProperties: false },
    initialState: { task: { done: 0 } },
  }) });
}

async function ticket(panelId: string, bearer: string): Promise<Response> {
  return SELF.fetch('https://test.local/api/panel-connections', { method: 'POST', headers: headers(bearer), body: JSON.stringify({ panelId, role: 'subscriber' }) });
}

it('publishes to an ungranted admin and lets admins list, read, and subscribe to all panels', async () => {
  const response = await publish();
  expect(response.status).toBe(201);
  const { panelId } = await response.json() as { panelId: string };
  for (const bearer of [ADMIN, OTHER_ADMIN]) {
    const list = await (await SELF.fetch(url, { headers: headers(bearer) })).json() as { panels: { panelId: string }[] };
    expect(list.panels.some(panel => panel.panelId === panelId)).toBe(true);
    expect((await SELF.fetch(`${url}/${panelId}`, { headers: headers(bearer) })).status).toBe(200);
    expect((await SELF.fetch(`${url}/${panelId}/state`, { headers: headers(bearer) })).status).toBe(200);
    expect((await ticket(panelId, bearer)).status).toBe(201);
  }
  const renewed = await SELF.fetch(`${url}/${panelId}/renew`, { method: 'POST',
    headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() },
    body: JSON.stringify({ protocolVersion: 2, expectedMetadataVersion: 1, expectedDefinitionRevision: 1, ttlSeconds: 120 }),
  });
  expect(renewed.status).toBe(200);
  const ended = await SELF.fetch(`${url}/${panelId}/lifecycle`, { method: 'POST',
    headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() },
    body: JSON.stringify({ protocolVersion: 2, action: 'complete', expectedMetadataVersion: 2,
      expectedDefinitionRevision: 1, expectedEpoch: null, expectedState: null, openRequests: 'reject' }),
  });
  expect(ended.status).toBe(200);
  expect((await SELF.fetch(`${url}/${panelId}`, { headers: headers(VIEWER) })).status).toBe(404);
  expect((await SELF.fetch(`${url}/${panelId}/state`, { headers: headers(VIEWER) })).status).toBe(404);
  expect((await ticket(panelId, VIEWER)).status).toBe(404);
});

it('requires explicit viewer grants for publication and removes reads and relay access after grant removal', async () => {
  expect((await publish(VIEWER)).status).toBe(404);
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(VIEWER, getTestAgentId()).run();
  const response = await publish(VIEWER);
  expect(response.status).toBe(201);
  const { panelId } = await response.json() as { panelId: string };
  expect((await SELF.fetch(`${url}/${panelId}`, { headers: headers(VIEWER) })).status).toBe(200);
  expect((await SELF.fetch(`${url}/${panelId}/state`, { headers: headers(VIEWER) })).status).toBe(200);
  expect((await ticket(panelId, VIEWER)).status).toBe(201);
  await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ?').bind(VIEWER).run();
  expect((await SELF.fetch(`${url}/${panelId}`, { headers: headers(VIEWER) })).status).toBe(404);
  expect((await SELF.fetch(`${url}/${panelId}/state`, { headers: headers(VIEWER) })).status).toBe(404);
  expect((await ticket(panelId, VIEWER)).status).toBe(404);
  expect(await (await SELF.fetch(url, { headers: headers(VIEWER) })).json()).toMatchObject({ panels: [] });
});
