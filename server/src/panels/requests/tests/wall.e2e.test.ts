// Verifies committed questionnaire mutations invalidate discovery through real relay sockets.
// Covers HTTP ordering, producer isolation, revisions, resolution, retries, and lost signals.
// Dependencies: Worker/D1 E2E fixtures and a controllable PanelRoom signal boundary.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, beforeEach, expect, it } from 'vitest';
import { hashApiKey } from '../../../middleware/auth';
import { authHeaders, getTestAgentId } from '../../../test-helpers';
import { base, BOSS, bossHeaders, create, publishPanel, questionnaire, read, setup, submit } from './support';
import { expectSignals, pending, signalProbe, wall } from './wall-support';

const otherKey = 'hb_questionnaire_wall_other';
const otherHeaders = { Authorization: `Bearer ${otherKey}`, 'Content-Type': 'application/json' };
beforeAll(async () => {
  await setup();
  await env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('questionnaire-other-agent', 'Other producer', await hashApiKey(otherKey)).run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(BOSS, 'questionnaire-other-agent').run();
});
beforeEach(async () => {
  await env.DB.prepare("UPDATE interaction_requests SET expires_at = '2000-01-01T00:00:00.000Z'").run();
});

function revise(requestId: string, blocking: boolean, expectedRevision = 1, expiresAt?: string): Promise<Response> {
  return SELF.fetch(`${base}/interaction-requests/${requestId}`, { method: 'PUT', headers: authHeaders(),
    body: JSON.stringify({ ...questionnaire, expectedRevision, blocking, expiresAt }) });
}
function withdraw(requestId: string, reason = 'No longer needed'): Promise<Response> {
  return SELF.fetch(`${base}/interaction-requests/${requestId}/withdraw`, { method: 'POST', headers: authHeaders(),
    body: JSON.stringify({ expectedRevision: 1, reason }) });
}
async function fixture() {
  const panelId = await publishPanel();
  const boss = await wall(bossHeaders), owner = await wall(authHeaders()), other = await wall(otherHeaders);
  const probe = await signalProbe();
  return { panelId, boss, owner, other, probe, close: async () => {
    await probe.restore();
    boss.socket.close(); owner.socket.close(); other.socket.close();
  } };
}

it('commits blocking publication before signaling and waits for the relay before HTTP success', async () => {
  const f = await fixture();
  f.probe.paused = true;
  let returned = false;
  try {
    expect(await pending()).toEqual([]);
    const publication = create(f.panelId).then(response => { returned = true; return response; });
    await expect.poll(() => f.probe.inputs.length).toBe(1);
    expect(await pending()).toMatchObject([{ panelId: f.panelId, blocking: true, requestRevision: 1 }]);
    expect(returned, 'HTTP must remain pending while the committed mutation waits for signaling').toBe(false);
    expect(f.probe.completed).toBe(0);
    f.probe.paused = false;
    const response = await publication;
    expect(response.status).toBe(201);
    expect(f.probe.completed, 'Relay signaling must finish before HTTP success').toBe(1);
    const { requestId } = await response.json<{ requestId: string }>();
    await expectSignals([f.boss, f.owner], 2);
    expect(f.other.frames).toEqual([{ kind: 'wall.changed' }]);
    expect(await pending(authHeaders())).toMatchObject([{ requestId, blocking: true }]);
    expect(await pending(otherHeaders)).toEqual([]);
    const panel = await (await SELF.fetch(`${base}/panels/${f.panelId}`, { headers: bossHeaders }))
      .json<{ lifecycle: { expiresAt: string } }>();
    expect(f.probe.inputs).toEqual([{ panelId: f.panelId, agentId: getTestAgentId(), expiresAt: panel.lifecycle.expiresAt }]);
  } finally { f.probe.paused = false; await f.close(); }
});

it('signals revisions changing blocking and expiry, then accepted submission and its safe retry', async () => {
  const f = await fixture();
  try {
    const { requestId } = await (await create(f.panelId)).json<{ requestId: string }>();
    const expiresAt = new Date(Date.now() + 600_000).toISOString();
    expect((await revise(requestId, false, 1, expiresAt)).status).toBe(200);
    expect(f.probe.completed).toBe(2);
    expect(f.probe.inputs[1].expiresAt).toBe(f.probe.inputs[0].expiresAt);
    expect(f.probe.inputs[1].expiresAt).not.toBe(expiresAt);
    await expectSignals([f.boss, f.owner], 3);
    expect(await pending()).toMatchObject([{ requestId, requestRevision: 2, blocking: false, expiresAt }]);
    expect((await revise(requestId, true, 2)).status).toBe(200);
    expect(f.probe.completed).toBe(3);
    await expectSignals([f.boss, f.owner], 4);
    expect(await pending()).toMatchObject([{ requestId, requestRevision: 3, blocking: true, expiresAt: null }]);
    const submissionId = crypto.randomUUID();
    for (let attempt = 0; attempt < 2; attempt++) {
      expect((await submit(requestId, { count: 4 }, submissionId, 3)).status).toBe(201);
      expect(f.probe.completed).toBe(4 + attempt);
      await expectSignals([f.boss, f.owner], 5 + attempt);
      expect(await pending()).toEqual([]);
      expect(await pending(authHeaders())).toEqual([]);
    }
    expect((await submit(requestId, { count: 5 }, submissionId, 3)).status).toBe(409);
    expect(f.probe.inputs).toHaveLength(5);
    expect(f.other.frames).toEqual([{ kind: 'wall.changed' }]);
  } finally { await f.close(); }
});

it('signals safe publication and withdrawal retries without signaling conflicts or rejected answers', async () => {
  const f = await fixture();
  try {
    const key = crypto.randomUUID();
    const receipt = await (await create(f.panelId, questionnaire, key)).json<{ requestId: string }>();
    expect(await (await create(f.panelId, questionnaire, key)).json()).toEqual(receipt);
    expect(f.probe.completed).toBe(2);
    expect((await create(f.panelId, { ...questionnaire, blocking: false }, key)).status).toBe(409);
    expect((await revise(receipt.requestId, false, 2)).status).toBe(409);
    expect((await submit(receipt.requestId, {})).status).toBe(422);
    expect(f.probe.inputs).toHaveLength(2);
    for (let attempt = 0; attempt < 2; attempt++) {
      expect((await withdraw(receipt.requestId)).status).toBe(200);
      expect(f.probe.completed).toBe(3 + attempt);
      await expectSignals([f.boss, f.owner], 4 + attempt);
      expect(await pending()).toEqual([]);
    }
    expect((await withdraw(receipt.requestId, 'Different reason')).status).toBe(409);
    expect((await submit(receipt.requestId)).status).toBe(409);
    expect(f.probe.inputs).toHaveLength(4);
    expect(f.other.frames).toEqual([{ kind: 'wall.changed' }]);
  } finally { await f.close(); }
});

it('keeps a committed publication successful when signaling fails and signals its retry', async () => {
  const f = await fixture();
  try {
    const key = crypto.randomUUID();
    f.probe.fail = true;
    const response = await create(f.panelId, questionnaire, key);
    expect(response.status).toBe(201);
    expect(f.probe.completed).toBe(1);
    const receipt = await response.json<{ requestId: string }>();
    expect(await pending()).toMatchObject([{ requestId: receipt.requestId, blocking: true }]);
    expect(await (await read(receipt.requestId)).json()).toMatchObject({ state: 'open', requestRevision: 1 });
    expect(f.boss.frames).toEqual([{ kind: 'wall.changed' }]);
    f.probe.fail = false;
    expect(await (await create(f.panelId, questionnaire, key)).json()).toEqual(receipt);
    expect(f.probe.completed).toBe(2);
    await expectSignals([f.boss, f.owner], 2);
    expect(f.other.frames).toEqual([{ kind: 'wall.changed' }]);
  } finally { await f.close(); }
});

it('does not signal a rolled-back answer transaction', async () => {
  const f = await fixture();
  try {
    const { requestId } = await (await create(f.panelId)).json<{ requestId: string }>();
    await env.DB.prepare("CREATE TRIGGER fail_wall_answer BEFORE INSERT ON interaction_deliveries BEGIN SELECT RAISE(ABORT, 'injected failure'); END").run();
    try { expect((await submit(requestId)).status).toBe(503); }
    finally { await env.DB.prepare('DROP TRIGGER fail_wall_answer').run(); }
    expect(f.probe.inputs).toHaveLength(1);
    expect(await pending()).toMatchObject([{ requestId, blocking: true }]);
    await expectSignals([f.boss, f.owner], 2);
    expect((await submit(requestId)).status).toBe(201);
    expect(f.probe.completed).toBe(2);
    await expectSignals([f.boss, f.owner], 3);
    expect(await pending()).toEqual([]);
    expect(f.other.frames).toEqual([{ kind: 'wall.changed' }]);
  } finally { await f.close(); }
});
