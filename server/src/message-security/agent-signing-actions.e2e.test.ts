// Agent signing for reply, peer, forward and boss-agent writes, and refused edits and group broadcasts.
// Verifies signature binding to the parent/target, downgrade rejection and replay handling.
// Depends on the test signer support module and shared database seeds.

import { env } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';
import {
  enrollment, messagePayload, newSigner, request, seedAgent, signedMessage, type TestAgent, type TestSigner,
} from './agent-signing-test-support';

beforeAll(seedDatabase);

const actionPayload = (agentId: string, action: Record<string, unknown>, body: string) =>
  messagePayload(agentId, { action, body, mode: null });

async function enrolled(name: string): Promise<{ agent: TestAgent; signer: TestSigner }> {
  const agent = await seedAgent(name);
  const signer = await newSigner();
  expect((await request('/agents/me/signing-keys', agent.token, 'POST', await enrollment(agent, signer))).status).toBe(201);
  return { agent, signer };
}

async function bossMessage(agentId: string): Promise<string> {
  const id = crypto.randomUUID().replaceAll('-', '');
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority)
    VALUES (?, ?, 'boss_to_agent', 'async', 'api', 'Status?', 'sent', 'normal')`).bind(id, agentId).run();
  return id;
}

it('signs a reply to its parent and refuses an unsigned or re-targeted one', async () => {
  const { agent, signer } = await enrolled('signed-reply');
  const parent = await bossMessage(agent.id);
  const other = await bossMessage(agent.id);
  expect((await request(`/messages/${parent}/reply`, agent.token, 'POST', { body: 'Done' })).status).toBe(401);
  const signed = await signedMessage(signer, actionPayload(agent.id,
    { kind: 'reply', message_id: parent, audience: { kind: 'boss' } }, 'Done'));
  expect((await request(`/messages/${other}/reply`, agent.token, 'POST', { body: 'Done', signed_message: signed })).status).toBe(401);
  const reply = await request(`/messages/${parent}/reply`, agent.token, 'POST', { body: 'Done', signed_message: signed });
  expect(reply.status).toBe(201);
  const row = await reply.json() as { id: string; metadata: Record<string, any> };
  expect(row.metadata.provenance.signature.signed_message).toBe(signed);
  const replay = await request(`/messages/${parent}/reply`, agent.token, 'POST', { body: 'Done', signed_message: signed });
  expect(replay.status).toBe(200);
  expect((await replay.json() as { id: string }).id).toBe(row.id);
});

it('keeps signed messages unedited, also after a boss reset, while unsigned agents keep editing', async () => {
  const { agent, signer } = await enrolled('signed-edit');
  const sent = await request('/messages', agent.token, 'POST',
    { body: 'Deploy finished', signed_message: await signedMessage(signer, messagePayload(agent.id)) });
  const id = (await sent.json() as { id: string }).id;
  expect((await request(`/messages/${id}`, agent.token, 'PATCH', { body: 'Deploy failed' })).status).toBe(409);
  expect((await request(`/messages/${id}`, agent.token, 'PATCH', { status: 'read' })).status).toBe(200);
  await seedBossToken('Edit Reset Boss', 'admin', 'boss-edit-reset');
  expect((await request(`/boss/agents/${agent.id}/signing-keys`, 'boss-edit-reset', 'DELETE')).status).toBe(200);
  expect((await request(`/messages/${id}`, agent.token, 'PATCH', { body: 'Deploy failed' })).status).toBe(409);
  const plain = await seedAgent('unsigned-edit');
  const draft = await request('/messages', plain.token, 'POST', { body: 'Draft' });
  const draftId = (await draft.json() as { id: string }).id;
  const edited = await request(`/messages/${draftId}`, plain.token, 'PATCH', { body: 'Final' });
  expect(edited.status).toBe(200);
  expect((await edited.json() as { body: string }).body).toBe('Final');
});

it('refuses group broadcast for a signing agent, signed or not', async () => {
  const { agent, signer } = await enrolled('signed-group');
  const group = await request('/groups', agent.token, 'POST', { name: 'signed-group-1' });
  const groupId = (await group.json() as { id: string }).id;
  expect((await request(`/groups/${groupId}/broadcast`, agent.token, 'POST', { body: 'Freeze' })).status).toBe(409);
  const signed = await signedMessage(signer, actionPayload(agent.id, { kind: 'group_broadcast', group_id: groupId }, 'Freeze'));
  expect((await request(`/groups/${groupId}/broadcast`, agent.token, 'POST', { body: 'Freeze', signed_message: signed })).status).toBe(409);
});

it('binds a peer send to the resolved recipient', async () => {
  const { agent, signer } = await enrolled('peer-sender');
  const peer = await seedAgent('peer-receiver');
  const resolved = await request('/messages/resolve-target', agent.token, 'POST', { to: 'peer-receiver' });
  expect(await resolved.json()).toMatchObject({ agent_id: peer.id, session_id: null });
  const wrong = await signedMessage(signer, messagePayload(agent.id, { action: { kind: 'send', audience: { kind: 'agent', agent_id: agent.id, session_id: null } } }));
  expect((await request('/messages', agent.token, 'POST', { body: 'Deploy finished', to: 'peer-receiver', signed_message: wrong })).status).toBe(401);
  const right = await signedMessage(signer, messagePayload(agent.id, { action: { kind: 'send', audience: { kind: 'agent', agent_id: peer.id, session_id: null } } }));
  expect((await request('/messages', agent.token, 'POST', { body: 'Deploy finished', to: 'peer-receiver', signed_message: right })).status).toBe(201);
});

it('requires signatures on forwards and boss-agent replies of a signing agent', async () => {
  const { agent, signer } = await enrolled('forward-boss-agent');
  const sent = await request('/messages', agent.token, 'POST',
    { body: 'Deploy finished', signed_message: await signedMessage(signer, messagePayload(agent.id)) });
  const id = (await sent.json() as { id: string }).id;
  expect((await request(`/messages/${id}/forward`, agent.token, 'POST', { channel: 'telegram' })).status).toBe(401);
  await env.DB.prepare("INSERT INTO bosses (name, role, agent_id) VALUES ('Agent Boss', 'admin', ?)").bind(agent.id).run();
  const worker = await seedAgent('boss-agent-worker');
  const ask = await request('/messages', worker.token, 'POST', { body: 'Approve?' });
  const askId = (await ask.json() as { id: string }).id;
  expect((await request(`/boss/inbox/${askId}/reply`, agent.token, 'POST', { body: 'Approve' })).status).toBe(401);
  const reply = await signedMessage(signer, actionPayload(agent.id, { kind: 'boss_reply', message_id: askId }, 'Approve'));
  expect((await request(`/boss/inbox/${askId}/reply`, agent.token, 'POST', { body: 'Approve', signed_message: reply })).status).toBe(201);
});
