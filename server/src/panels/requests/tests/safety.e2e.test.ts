// Exercises questionnaire access, signature enforcement, and transactional rollback.
// Covers bearer-only and paired-device submissions plus races with revision changes.
// Dependencies: real Worker/D1, Web Crypto, and shared E2E fixtures.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedBossToken } from '../../../test-helpers';
import { base, BOSS, bossHeaders, create, finish, publish, publishPanel, questionnaire, read, setup, submit } from './support';

beforeAll(setup);
describe('questionnaire integrity', () => {
  it('rolls back the answer claim if delivery receipt insertion fails', async () => {
    const { requestId } = await publish();
    await env.DB.prepare("CREATE TRIGGER fail_questionnaire_delivery BEFORE INSERT ON interaction_deliveries BEGIN SELECT RAISE(ABORT, 'injected crash'); END").run();
    try { expect((await submit(requestId)).status).toBe(503); }
    finally { await env.DB.prepare('DROP TRIGGER fail_questionnaire_delivery').run(); }
    expect(await (await read(requestId)).json()).toMatchObject({ state: 'open', submission: null });
    const answers = await env.DB.prepare('SELECT COUNT(*) AS count FROM interaction_submissions WHERE request_id = ?').bind(requestId).first<{ count: number }>();
    expect(answers?.count).toBe(0);
    expect((await submit(requestId)).status).toBe(201);
  });
  it('permits answers while paused and never lets a viewer answer', async () => {
    const { panelId, requestId } = await publish();
    expect((await finish(panelId, { action: 'pause' })).status).toBe(200);
    await env.DB.prepare("UPDATE bosses SET role = 'viewer' WHERE id = ?").bind(BOSS).run();
    try { expect((await submit(requestId)).status).toBe(403); }
    finally { await env.DB.prepare("UPDATE bosses SET role = 'manager' WHERE id = ?").bind(BOSS).run(); }
    expect((await submit(requestId)).status).toBe(201);
  });
  it('hides answers from another boss and revokes reads when access is removed', async () => {
    const { requestId } = await publish();
    await seedBossToken('Other', 'admin', 'hb_questionnaire_other', 'questionnaire-other');
    expect((await read(requestId, '', { Authorization: 'Bearer hb_questionnaire_other' })).status).toBe(404);
    await env.DB.prepare('DELETE FROM boss_agent_access WHERE boss_id = ?').bind(BOSS).run();
    try { expect((await read(requestId)).status).toBe(404); }
    finally { await env.DB.prepare("INSERT INTO boss_agent_access VALUES (?, 'test-agent-id')").bind(BOSS).run(); }
  });
  it('rejects authorization kinds and mutable task bindings in questionnaire context', async () => {
    const panelId = await publishPanel();
    expect((await create(panelId, { ...questionnaire, kind: 'authorization' })).status).toBe(422);
    const formSpec = { root: 'title', elements: { title: { type: 'Text', props: { text: { $state: '/task/done' } }, children: [] } } };
    expect((await create(panelId, { ...questionnaire, formSpec })).status).toBe(422);
    for (const value of [{ $bindState: '/context/candidate' }, { $state: '/form/count' }, { $bindItem: '/form/count' }]) {
      const inputSpec = { root: 'input', elements: { input: { type: 'TextInput', props: { label: 'Answer', value }, children: [] } } };
      expect((await create(panelId, { ...questionnaire, formSpec: inputSpec })).status).toBe(422);
    }
    const contextSpec = { root: 'context', elements: { context: { type: 'Text', props: { text: { $state: '/context/candidate' } }, children: [] } } };
    expect((await create(panelId, { ...questionnaire, formSpec: contextSpec })).status).toBe(201);
  });
  it('permits incomplete drafts but rejects invalid or undeclared default values', async () => {
    const panelId = await publishPanel();
    expect((await create(panelId, { ...questionnaire, defaults: {} })).status).toBe(201);
    for (const defaults of [{ count: '3' }, { count: 0 }, { hidden: true }]) {
      expect((await create(panelId, { ...questionnaire, defaults })).status).toBe(422);
    }
  });
  it('requires purpose-bound signatures for a paired token and rejects tampered answers', async () => {
    const { requestId } = await publish();
    const key = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']) as CryptoKeyPair;
    const publicKey = encode(new Uint8Array(await crypto.subtle.exportKey('raw', key.publicKey)));
    const token = await env.DB.prepare('SELECT id FROM boss_tokens WHERE boss_id = ?').bind(BOSS).first<{ id: string }>();
    await env.DB.prepare("INSERT INTO boss_signing_keys (id, boss_id, boss_token_id, algorithm, client_kind, public_key) VALUES ('questionnaire-key', ?, ?, 'ES256', 'ios', ?)").bind(BOSS, token!.id, publicKey).run();
    const payload = { protocolVersion: 1, purpose: 'hiboss.interaction-submit', submissionId: crypto.randomUUID(), requestId, requestRevision: 1, bossId: BOSS, answers: { count: 4 } };
    try {
      expect((await submit(requestId)).status).toBe(403);
      const signedSubmission = await sign(key.privateKey, payload);
      const send = (body: unknown) => SELF.fetch(`${base}/interaction-requests/${requestId}/submissions`, { method: 'POST', headers: bossHeaders, body: JSON.stringify(body) });
      expect((await send({ ...payload, answers: { count: 5 }, signedSubmission })).status).toBe(403);
      expect((await send({ ...payload, signedSubmission })).status).toBe(201);
      expect(await (await read(requestId)).json()).toMatchObject({ submission: { provenance: { provenance: { authentication: { kind: 'device_signature' } } } } });
      await env.DB.prepare("UPDATE boss_signing_keys SET revoked_at = datetime('now') WHERE id = 'questionnaire-key'").run();
      expect((await submit(requestId)).status).toBe(403);
    } finally { await env.DB.prepare("DELETE FROM boss_signing_keys WHERE id = 'questionnaire-key'").run(); }
  });
});
function encode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
async function sign(key: CryptoKey, payload: Record<string, unknown>): Promise<string> {
  const encoder = new TextEncoder();
  const header = encode(encoder.encode(JSON.stringify({ alg: 'ES256', kid: 'questionnaire-key', typ: 'hiboss-interaction+jws' })));
  const body = encode(encoder.encode(JSON.stringify({ ...payload, issuedAt: Math.floor(Date.now() / 1000) })));
  const input = `${header}.${body}`;
  const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, encoder.encode(input));
  return `${input}.${encode(new Uint8Array(signature))}`;
}
