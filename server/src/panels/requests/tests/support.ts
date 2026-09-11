// Shared authenticated HTTP fixtures for durable questionnaire E2E flows.
// Exports setup, publication, request, submission, and lifecycle helpers.
// Dependencies: cloudflare:test, Vitest, and the real interaction migration.

import { env, SELF } from 'cloudflare:test';
import { expect } from 'vitest';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../../../test-helpers';

export const BOSS = 'questionnaire-boss';
export const bossHeaders = { Authorization: 'Bearer hb_questionnaire_boss', 'Content-Type': 'application/json' };
export const base = 'https://test.local/api';
export const questionnaire = {
  kind: 'intake', title: 'Choose test settings', blocking: true, priority: 'normal',
  catalogId: 'hiboss.panel', catalogVersion: 1, context: { candidate: 'build-42' }, defaults: { count: 3 },
  answerSchema: { type: 'object', properties: { count: { type: 'integer', minimum: 1, maximum: 10 } }, required: ['count'], additionalProperties: false },
  formSpec: { root: 'count', elements: { count: { type: 'NumberInput', props: { label: 'Count', value: { $bindState: '/form/count' } }, children: [] } } },
};
export async function setup(): Promise<void> {
  await seedDatabase();
  await seedBossToken('Questionnaire boss', 'manager', 'hb_questionnaire_boss', BOSS);
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access VALUES (?, ?)').bind(BOSS, getTestAgentId()).run();
  await env.DB.prepare('INSERT OR IGNORE INTO sessions (id, agent_id) VALUES (?, ?)').bind('questionnaire-session', getTestAgentId()).run();
}
export async function publishPanel(): Promise<string> {
  const response = await SELF.fetch(`${base}/panels`, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() }, body: JSON.stringify({
    protocolVersion: 2, targetBossId: BOSS, sessionId: 'questionnaire-session', taskKey: 'questions', title: 'Questionnaire', catalogId: 'hiboss.panel', catalogVersion: 1,
    spec: { root: 'metric', elements: { metric: { type: 'Metric', props: { label: 'Done', value: { $state: '/task/done' } }, children: [] } } },
    stateSchema: { type: 'object', properties: { task: { type: 'object', properties: { done: { type: 'integer' } }, required: ['done'], additionalProperties: false } }, required: ['task'], additionalProperties: false }, initialState: { task: { done: 0 } },
  }) });
  expect(response.status).toBe(201);
  return (await response.json<{ panelId: string }>()).panelId;
}
export function create(panelId: string, body: unknown = questionnaire, key = crypto.randomUUID()): Promise<Response> {
  return SELF.fetch(`${base}/panels/${panelId}/requests`, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': key }, body: JSON.stringify(body) });
}
export async function publish(): Promise<{ panelId: string; requestId: string }> {
  const panelId = await publishPanel();
  const response = await create(panelId);
  expect(response.status).toBe(201);
  return { panelId, requestId: (await response.json<{ requestId: string }>()).requestId };
}
export function submit(requestId: string, answers: unknown = { count: 4 }, submissionId = crypto.randomUUID(), revision = 1): Promise<Response> {
  return SELF.fetch(`${base}/interaction-requests/${requestId}/submissions`, { method: 'POST', headers: bossHeaders,
    body: JSON.stringify({ protocolVersion: 1, purpose: 'hiboss.interaction-submit', submissionId, requestId, requestRevision: revision, bossId: BOSS, answers }) });
}
export function read(requestId: string, suffix = '', headers: Record<string, string> = bossHeaders): Promise<Response> {
  return SELF.fetch(`${base}/interaction-requests/${requestId}${suffix}`, { headers });
}
export function finish(panelId: string, extra: Record<string, unknown> = {}): Promise<Response> {
  return SELF.fetch(`${base}/panels/${panelId}/lifecycle`, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() },
    body: JSON.stringify({ protocolVersion: 2, action: 'complete', expectedMetadataVersion: 1, expectedDefinitionRevision: 1, expectedEpoch: null, expectedState: null, openRequests: 'reject', ...extra }) });
}
