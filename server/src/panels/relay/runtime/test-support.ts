// Authenticated publication and WebSocket harness for lifecycle integration flows.
// Exports seed, publish, connect, command, and checkpoint helpers.
// Dependencies: Cloudflare test runtime and shared database seeds.

import { env, SELF } from 'cloudflare:test';
import { authHeaders, getTestAgentId, seedBossToken, seedDatabase } from '../../../test-helpers';
import type { Checkpoint } from '../../lifecycle/types';

export const bossId = 'relay-v2-boss';
export const bossHeaders = { Authorization: 'Bearer hb_relay_v2_boss_00000000000000000001', 'Content-Type': 'application/json' };
export const url = 'https://test.local/api/panels';
export async function seed(): Promise<void> {
  await seedDatabase();
  await seedBossToken('Relay Boss', 'manager', bossHeaders.Authorization.slice(7), bossId);
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(bossId, getTestAgentId()).run();
  await env.DB.prepare('INSERT OR IGNORE INTO sessions (id, agent_id, label) VALUES (?, ?, ?)').bind('relay-v2-session', getTestAgentId(), 'relay tests').run();
}
export async function publish(lifecycle: Record<string, unknown> = { mode: 'monitor', expectedUpdateIntervalSeconds: 5 }): Promise<string> {
  const response = await SELF.fetch(url, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() }, body: JSON.stringify({
    protocolVersion: 2, targetBossId: bossId, sessionId: 'relay-v2-session', taskKey: 'relay', title: 'Relay test', catalogId: 'hiboss.panel', catalogVersion: 1,
    spec: { root: 'm', elements: { m: { type: 'Metric', props: { label: 'Done', value: { $state: '/task/done' } }, children: [] } } },
    stateSchema: { type: 'object', properties: { task: { type: 'object', properties: { done: { type: 'integer', minimum: 0 }, items: { type: 'array', items: { type: 'string' }, maxItems: 20 } }, required: ['done', 'items'], additionalProperties: false } }, required: ['task'], additionalProperties: false },
    initialState: { task: { done: 0, items: [] } }, lifecycle,
  }) });
  if (response.status !== 201) throw new Error(await response.text());
  return (await response.json<{ panelId: string }>()).panelId;
}
export type Frame = Partial<Checkpoint> & { kind: string; code?: string; snapshot?: Checkpoint };
export async function connect(panelId: string, subscriber = false) {
  const ticketResponse = await SELF.fetch('https://test.local/api/panel-connections', { method: 'POST', headers: subscriber ? bossHeaders : authHeaders(), body: JSON.stringify({ panelId, role: subscriber ? 'subscriber' : 'producer' }) });
  const ticket = await ticketResponse.json<{ ticket: string }>();
  const response = await SELF.fetch('https://test.local/api/panel-relay', { headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket.ticket } });
  const socket = response.webSocket;
  if (!socket) throw new Error('No WebSocket');
  socket.accept();
  const frames: Frame[] = [];
  socket.addEventListener('message', event => { frames.push(JSON.parse(String(event.data)) as Frame); });
  const send = (body: Record<string, unknown>) => socket.send(JSON.stringify({ protocolVersion: 2, panelId, definitionRevision: 1, ...body }));
  async function next(kind: string, start = 0): Promise<Frame> {
    for (let attempt = 0; attempt < 200; attempt++) {
      const frame = frames.slice(start).find(f => f.kind === kind);
      if (frame) return frame;
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    throw new Error(`Missing ${kind}: ${JSON.stringify(frames)}`);
  }
  send({ kind: 'subscribe' });
  await next('state.snapshot');
  return { socket, frames, send, next };
}
export async function claim(connection: Awaited<ReturnType<typeof connect>>, takeoverEpoch?: string): Promise<string> {
  const start = connection.frames.length;
  connection.send({ kind: 'lease.claim', requestId: crypto.randomUUID(), ...(takeoverEpoch ? { takeoverEpoch } : {}) });
  const frame = await connection.next('lease.ack', start);
  if (!frame.epoch) throw new Error('Missing server epoch');
  return frame.epoch;
}
export async function state(id: string): Promise<Checkpoint> {
  return (await SELF.fetch(`${url}/${id}/state`, { headers: bossHeaders })).json<Checkpoint>();
}
export async function control(id: string, action: string, metadataVersion: number, current: Checkpoint): Promise<Response> {
  return SELF.fetch(`${url}/${id}/lifecycle`, { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() }, body: JSON.stringify({
    protocolVersion: 2, action, expectedMetadataVersion: metadataVersion, expectedDefinitionRevision: current.definitionRevision,
    expectedEpoch: current.leaseExpiresAt && Date.parse(current.leaseExpiresAt) > Date.now() ? current.epoch : null,
    expectedState: { epoch: current.epoch, sequence: current.sequence }, openRequests: 'reject',
  }) });
}
