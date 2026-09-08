// End-to-end lifecycle flows through authenticated HTTP and the durable relay.
// Covers final snapshots, pause/resume, immutable outcomes, and boss placement.
// Dependencies: Cloudflare test runtime, Vitest, and database fixtures.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../../test-helpers';

const bossId = 'lifecycle-boss';
const bossToken = 'hb_lifecycle_boss_0000000000000000000001';
const bossHeaders = { Authorization: `Bearer ${bossToken}`, 'Content-Type': 'application/json' };
const url = 'https://test.local/api/panels';
interface Detail { panelId: string; metadataVersion: number; lifecycle: { taskState: string; dismissAt: string | null }; }

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Lifecycle Boss', 'manager', bossToken, bossId);
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(bossId, getTestAgentId()).run();
  await env.DB.prepare('INSERT OR IGNORE INTO sessions (id, agent_id, label) VALUES (?, ?, ?)').bind('lifecycle-session', getTestAgentId(), 'lifecycle').run();
});

async function publish(): Promise<string> {
  const response = await SELF.fetch(url, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() }, body: JSON.stringify({
    protocolVersion: 2, targetBossId: bossId, sessionId: 'lifecycle-session', taskKey: 'tests', title: 'Lifecycle tests', catalogId: 'hiboss.panel', catalogVersion: 1,
    spec: { root: 'metric', elements: { metric: { type: 'Metric', props: { label: 'Done', value: { $state: '/task/done' } }, children: [] } } },
    stateSchema: { type: 'object', properties: { task: { type: 'object', properties: { done: { type: 'integer', minimum: 0 } }, required: ['done'], additionalProperties: false } }, required: ['task'], additionalProperties: false },
    initialState: { task: { done: 0 } },
  }) });
  expect(response.status).toBe(201);
  return (await response.json() as { panelId: string }).panelId;
}

async function command(id: string, action: string, version: number, key = crypto.randomUUID(), extra: Record<string, unknown> = {}): Promise<Response> {
  return SELF.fetch(`${url}/${id}/lifecycle`, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': key }, body: JSON.stringify({
    protocolVersion: 2, action, expectedMetadataVersion: version, expectedDefinitionRevision: 1,
    expectedEpoch: null, expectedState: null, openRequests: 'reject', ...extra,
  }) });
}

async function detail(id: string): Promise<Detail> {
  return (await SELF.fetch(`${url}/${id}`, { headers: bossHeaders })).json<Detail>();
}

describe('dynamic card lifecycle', () => {
  it('completes with final data, reloads the result, and deduplicates the finish', async () => {
    const id = await publish();
    const key = crypto.randomUUID();
    const extra = { finalTask: { done: 24 }, result: { title: '24 tests passed' } };
    const response = await command(id, 'complete', 1, key, extra);
    expect(response.status).toBe(200);
    const receipt = await response.json<{ operationId: string }>();
    expect(await (await SELF.fetch(`${url}/${id}/operations/${receipt.operationId}`, { headers: bossHeaders })).json()).toEqual(receipt);
    expect(await (await command(id, 'complete', 1, key, extra)).json()).toEqual(receipt);
    expect((await detail(id)).lifecycle.taskState).toBe('completed');
    const state = await (await SELF.fetch(`${url}/${id}/state`, { headers: bossHeaders })).json();
    expect(state).toMatchObject({ task: { done: 24 } });
    expect((await command(id, 'resume', 2)).status).toBe(409);
  });

  it('pauses and resumes with metadata CAS and rejects stale reports', async () => {
    const id = await publish();
    expect((await command(id, 'pause', 1)).status).toBe(200);
    expect((await detail(id)).lifecycle.taskState).toBe('paused');
    expect((await command(id, 'complete', 1)).status).toBe(409);
    expect((await command(id, 'resume', 2)).status).toBe(200);
    expect((await detail(id)).lifecycle.taskState).toBe('running');
  });

  it('retains failed outcomes until acknowledgement and keeps archive separate from execution', async () => {
    const id = await publish();
    const archive = await SELF.fetch(`${url}/${id}/preferences`, { method: 'PUT', headers: bossHeaders, body: JSON.stringify({ expectedPreferenceVersion: 0, placement: 'archived' }) });
    expect(archive.status).toBe(200);
    expect((await detail(id)).lifecycle.taskState).toBe('running');
    expect((await command(id, 'fail', 1, crypto.randomUUID(), { result: { code: 'source_unavailable', title: 'Source unavailable' } })).status).toBe(200);
    expect((await detail(id)).lifecycle).toMatchObject({ taskState: 'failed', dismissAt: null });
  });

  it('rejects invalid final data without ending the task and permits cancellation', async () => {
    const id = await publish();
    expect((await command(id, 'complete', 1, crypto.randomUUID(), { finalTask: { done: -1 } })).status).toBe(422);
    expect((await detail(id)).lifecycle.taskState).toBe('running');
    expect((await command(id, 'cancel', 1, crypto.randomUUID(), { result: { title: 'Cancelled by executor' } })).status).toBe(200);
    expect((await detail(id)).lifecycle.taskState).toBe('cancelled');
  });
  it('does not let producers dismiss a failure immediately', async () => {
    const id = await publish();
    expect((await command(id, 'fail', 1, crypto.randomUUID(), { result: { code: 'failed', title: 'Failed' }, dismissal: { policy: 'immediate' } })).status).toBe(422);
    expect((await detail(id)).lifecycle.taskState).toBe('running');
  });

});
