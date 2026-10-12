// Agent message signing against the real Worker and D1: enrollment, admission, downgrade and replay.
// Covers send, server-owned metadata stripping, endorsement, boss reset and credential revocation.
// Depends on the test signer support module and shared database seeds.

import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';
import {
  enrollment, messagePayload, newSigner, now, request, seedAgent, signedMessage,
} from './agent-signing-test-support';

beforeAll(seedDatabase);

type Row = { id: string; body: string; metadata: string | null };
const stored = (id: string) => env.DB.prepare('SELECT id, body, metadata FROM messages WHERE id = ?').bind(id).first<Row>();
const meta = (row: Row | null) => JSON.parse(row?.metadata ?? '{}') as Record<string, any>;

it('replaces client-supplied provenance with server attribution on an unsigned send', async () => {
  const agent = await seedAgent('strip-meta');
  const forged = { source: 'ios', provenance: { version: 1, source: 'ios' }, options_resolved: true, content: 'details' };
  const response = await request('/messages', agent.token, 'POST', { body: 'hello', metadata: forged });
  expect(response.status).toBe(201);
  const metadata = meta(await stored((await response.json() as { id: string }).id));
  expect(metadata).toMatchObject({ source: 'agent', content: 'details' });
  expect(metadata.provenance).toMatchObject({ source: 'agent', actor: { kind: 'agent', id: agent.id },
    authentication: { kind: 'api_key', credential_id: agent.keyId }, signature: { status: 'not_configured' } });
  expect(metadata.options_resolved).toBeUndefined();
});

it('enrolls on first use, notifies the boss, then rejects unsigned and tampered sends', async () => {
  const agent = await seedAgent('first-use');
  const signer = await newSigner();
  const enrolled = await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, signer));
  expect(enrolled.status).toBe(201);
  expect(await enrolled.json()).toMatchObject({ key_id: signer.keyId, enrolled_via: 'first_use' });
  const again = await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, signer));
  expect(again.status).toBe(200);
  const notice = await env.DB.prepare("SELECT body FROM messages WHERE agent_id = ? AND body LIKE 'Message signing enabled%'")
    .bind(agent.id).first();
  expect(notice).not.toBeNull();
  expect((await request('/messages', agent.token, 'POST', { body: 'unsigned' })).status).toBe(401);
  const tampered = await signedMessage(signer, messagePayload(agent.id, { body: 'approve staging' }));
  expect((await request('/messages', agent.token, 'POST', { body: 'approve prod', signed_message: tampered })).status).toBe(401);
  const stale = await signedMessage(signer, messagePayload(agent.id, { issued_at: now() - 600 }));
  expect((await request('/messages', agent.token, 'POST', { body: 'Deploy finished', signed_message: stale })).status).toBe(401);
  const otherKey = await signedMessage(await newSigner(), messagePayload(agent.id));
  expect((await request('/messages', agent.token, 'POST', { body: 'Deploy finished', signed_message: otherKey })).status).toBe(401);
});

it('stores a signed ask with its signature and deduplicates a replay', async () => {
  const agent = await seedAgent('signed-send');
  const signer = await newSigner();
  await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, signer));
  const content = { content: '## Plan' };
  const signed = await signedMessage(signer, messagePayload(agent.id, {
    body: 'Ship it?', mode: 'blocking', timeout: 120, options: ['Yes', 'No'], metadata: content,
  }));
  const body = { body: 'Ship it?', mode: 'blocking', timeout: 120, options: ['Yes', 'No'], metadata: content, signed_message: signed };
  const first = await request('/messages', agent.token, 'POST', body);
  expect(first.status).toBe(201);
  const id = (await first.json() as { id: string }).id;
  const metadata = meta(await stored(id));
  expect(metadata.provenance).toMatchObject({ source: 'agent', authentication: { kind: 'agent_signature', credential_id: agent.keyId },
    signature: { scheme: 'JWS-ES256', key_id: signer.keyId, public_key: signer.publicKey, signed_message: signed } });
  expect(metadata).toMatchObject({ options: ['Yes', 'No'], content: '## Plan', ask_deadline: true });
  const replay = await request('/messages', agent.token, 'POST', body);
  expect(replay.status).toBe(200);
  expect((await replay.json() as { id: string }).id).toBe(id);
  const swapped = { ...body, options: ['Yes', 'Yes, and deploy prod'] };
  expect((await request('/messages', agent.token, 'POST', swapped)).status).toBe(401);
});

it('binds a second credential only with an endorsement and enforces signing on it', async () => {
  const agent = await seedAgent('endorse');
  const first = await newSigner();
  await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, first));
  const minted = await request('/agents/me/keys', agent.token, 'POST', { label: 'second' });
  const grant = await minted.json() as { id: string; key: string };
  const second = { id: agent.id, token: grant.key, keyId: grant.id };
  expect((await request('/messages', second.token, 'POST', { body: 'unsigned via fresh credential' })).status).toBe(401);
  const signer = await newSigner();
  expect((await request('/agents/me/signing-keys', second.token, 'POST', await enrollment(second, signer))).status).toBe(403);
  const endorsed = await request('/agents/me/signing-keys', second.token, 'POST', await enrollment(second, signer, first));
  expect(endorsed.status).toBe(201);
  expect(await endorsed.json()).toMatchObject({ enrolled_via: 'endorsed' });
  const signed = await signedMessage(signer, messagePayload(agent.id));
  expect((await request('/messages', second.token, 'POST', { body: 'Deploy finished', signed_message: signed })).status).toBe(201);
});

it('lets a boss reset signing so the agent can enroll again, and drops keys of revoked credentials', async () => {
  const agent = await seedAgent('reset');
  const signer = await newSigner();
  await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, signer));
  await seedBossToken('Reset Boss', 'admin', 'boss-reset-token');
  const listed = await request(`/boss/agents/${agent.id}/signing-keys`, 'boss-reset-token');
  expect(await listed.json()).toMatchObject({ keys: [{ key_id: signer.keyId }] });
  const reset = await request(`/boss/agents/${agent.id}/signing-keys`, 'boss-reset-token', 'DELETE');
  expect(await reset.json()).toEqual({ revoked: 1 });
  expect((await request('/messages', agent.token, 'POST', { body: 'unsigned after reset' })).status).toBe(201);
  const next = await newSigner();
  expect((await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, next))).status).toBe(201);
  await env.DB.prepare("UPDATE agent_keys SET revoked_at = datetime('now') WHERE id = ?").bind(agent.keyId).run();
  const status = await env.DB.prepare(`SELECT COUNT(*) AS live FROM agent_signing_keys s JOIN agent_keys k ON k.id = s.agent_key_id
    WHERE s.agent_id = ? AND s.revoked_at IS NULL AND k.revoked_at IS NULL`).bind(agent.id).first<{ live: number }>();
  expect(status?.live).toBe(0);
});

it('keeps requiring signatures after a bearer holder revokes every signing credential', async () => {
  const agent = await seedAgent('revoke-downgrade');
  await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, await newSigner()));
  const minted = await (await request('/agents/me/keys', agent.token, 'POST', { label: 'attacker' })).json() as { id: string; key: string };
  expect((await request(`/agents/me/keys/${agent.keyId}`, minted.key, 'DELETE')).status).toBe(200);
  expect((await request('/messages', minted.key, 'POST', { body: 'unsigned after revocation' })).status).toBe(401);
  const attacker = { id: agent.id, token: minted.key, keyId: minted.id };
  expect((await request('/agents/me/signing-keys', minted.key, 'POST', await enrollment(attacker, await newSigner()))).status).toBe(403);
  const status = await (await request('/agents/me/signing-keys', minted.key)).json() as { required: boolean };
  expect(status.required).toBe(true);
});
