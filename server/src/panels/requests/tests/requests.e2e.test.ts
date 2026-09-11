// Verifies durable answers, exact revision binding, and lifecycle races via HTTP.
// Covers retries, validation, competing devices, withdrawal, and agent readback.
// Dependencies: isolated D1/Worker fixtures and Vitest.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { authHeaders } from '../../../test-helpers';
import { base, bossHeaders, create, finish, publish, publishPanel, questionnaire, read, setup, submit } from './support';

beforeAll(setup);
describe('durable questionnaires', () => {
  it('persists typed answers, an event and delivery receipt, and deduplicates retries', async () => {
    const { requestId } = await publish();
    const before = await (await read(requestId)).json();
    expect(before).toMatchObject({ state: 'open', submission: null, definition: { defaults: { count: 3 } } });
    const id = crypto.randomUUID();
    const response = await submit(requestId, { count: 4 }, id);
    expect(response.status).toBe(201);
    const receipt = await response.json();
    expect(await (await submit(requestId, { count: 4 }, id)).json()).toEqual(receipt);
    expect((await submit(requestId, { count: 5 }, id)).status).toBe(409);
    const saved = await (await read(requestId, '', authHeaders())).json();
    expect(saved).toMatchObject({ state: 'accepted', submission: { submissionId: id, answers: { count: 4 }, delivery: 'pending' } });
    const event = await env.DB.prepare("SELECT COUNT(*) AS count FROM session_events WHERE kind = 'interaction.submitted' AND json_extract(payload, '$.submissionId') = ?").bind(id).first<{ count: number }>();
    expect(event?.count).toBe(1);
    expect((await SELF.fetch(`${base}/interaction-requests/${requestId}/submissions/${id}/ack`, { method: 'POST', headers: authHeaders() })).status).toBe(200);
    expect(await (await read(requestId)).json()).toMatchObject({ submission: { delivery: 'delivered' } });
  });
  it('validates required, typed and unexpected answers without resolving the request', async () => {
    const { requestId } = await publish();
    for (const answers of [{}, { count: '4' }, { count: 11 }, { count: 4, hidden: true }]) expect((await submit(requestId, answers)).status).toBe(422);
    expect(await (await read(requestId)).json()).toMatchObject({ state: 'open' });
  });
  it('accepts exactly one competing device and preserves the winning answer', async () => {
    const { requestId } = await publish();
    const responses = await Promise.all([submit(requestId, { count: 4 }), submit(requestId, { count: 5 })]);
    expect(responses.map(r => r.status).sort()).toEqual([201, 409]);
    for (const response of responses) await response.arrayBuffer();
    const row = await env.DB.prepare('SELECT COUNT(*) AS count FROM interaction_submissions WHERE request_id = ?').bind(requestId).first<{ count: number }>();
    expect(row?.count).toBe(1);
  });
  it('pins immutable revisions and rejects an old draft after replacement', async () => {
    const { requestId } = await publish();
    const response = await SELF.fetch(`${base}/interaction-requests/${requestId}`, { method: 'PUT', headers: authHeaders(),
      body: JSON.stringify({ expectedRevision: 1, ...questionnaire, title: 'Revised settings' }) });
    expect(response.status).toBe(200);
    expect((await submit(requestId)).status).toBe(409);
    expect(await (await read(requestId, '?revision=1')).json()).toMatchObject({ requestRevision: 2, definitionRevision: 1, definition: { title: 'Choose test settings' } });
    expect((await submit(requestId, { count: 4 }, crypto.randomUUID(), 2)).status).toBe(201);
  });
  it('refuses completion with open questions and withdraws only when explicitly requested', async () => {
    const { panelId, requestId } = await publish();
    expect((await finish(panelId)).status).toBe(409);
    expect((await finish(panelId, { openRequests: 'withdraw', withdrawalReason: 'Run cancelled' })).status).toBe(200);
    expect((await submit(requestId)).status).toBe(409);
    expect(await (await read(requestId)).json()).toMatchObject({ state: 'withdrawn', withdrawalReason: 'Run cancelled', submission: null });
  });
  it('resolves answer versus completion races without losing an accepted answer', async () => {
    const { panelId, requestId } = await publish();
    const [answer, ended] = await Promise.all([submit(requestId), finish(panelId, { openRequests: 'withdraw', withdrawalReason: 'Finished' })]);
    expect(ended.status).toBe(200);
    expect([201, 409]).toContain(answer.status);
    const current = await (await read(requestId)).json<{ state: string; submission: unknown }>();
    expect(current.state).toBe(answer.status === 201 ? 'accepted' : 'withdrawn');
    expect(current.submission !== null).toBe(answer.status === 201);
  });
  it('deduplicates publication and refuses questions on an ended panel', async () => {
    const panelId = await publishPanel();
    const key = crypto.randomUUID();
    const initial = await (await create(panelId, questionnaire, key)).json();
    expect(await (await create(panelId, questionnaire, key)).json()).toEqual(initial);
    expect((await create(panelId, { ...questionnaire, title: 'Different' }, key)).status).toBe(409);
    const other = await publishPanel();
    expect((await finish(other)).status).toBe(200);
    expect((await create(other)).status).toBe(409);
  });
  it('rejects expired submissions and does not convert defaults into an answer', async () => {
    const { requestId } = await publish();
    await env.DB.prepare("UPDATE interaction_requests SET expires_at = '2000-01-01T00:00:00.000Z' WHERE request_id = ?").bind(requestId).run();
    expect((await submit(requestId)).status).toBe(409);
    expect(await (await read(requestId)).json()).toMatchObject({ state: 'expired', submission: null });
  });
});
