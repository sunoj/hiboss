// Exercises wall discovery and isolation through authenticated HTTP and relay sockets.
// Exports Vitest E2E coverage; dependencies: SELF, real D1, and relay test helpers.

import { env, SELF, runInDurableObject } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, getTestAgentId } from '../../test-helpers';
import { hashApiKey } from '../../middleware/auth';
import { bossHeaders, bossId, claim, connect, control, publish, seed, state } from './runtime/test-support';
import type { PanelRoom } from './room';

beforeAll(seed);

async function wall(headers: Record<string, string>) {
  const issued = await SELF.fetch('https://test.local/api/panel-wall-connections', {
    method: 'POST', headers, body: JSON.stringify({ targetBossId: bossId }),
  });
  expect(issued.status).toBe(201);
  const { ticket } = await issued.json<{ ticket: string }>();
  const response = await SELF.fetch('https://test.local/api/panel-relay', {
    headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket },
  });
  const socket = response.webSocket;
  if (!socket) throw new Error('Missing wall socket');
  socket.accept();
  const frames: { kind: string }[] = [];
  socket.addEventListener('message', event => { frames.push(JSON.parse(String(event.data))); });
  socket.send(JSON.stringify({ protocolVersion: 2, kind: 'wall.subscribe', panelId: 'wall' }));
  await expect.poll(() => frames.length).toBe(1);
  expect(frames[0]).toEqual({ kind: 'wall.changed' });
  return { socket, frames };
}

it('signals publication and completion to the boss and owning agent only', async () => {
  const otherKey = 'hb_wall_other_agent_000000000000000001';
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind('wall-other', 'Other wall agent', await hashApiKey(otherKey)).run();
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)')
    .bind(bossId, 'wall-other').run();
  const boss = await wall(bossHeaders);
  const owner = await wall(authHeaders());
  const other = await wall({ Authorization: `Bearer ${otherKey}`, 'Content-Type': 'application/json' });
  try {
    const id = await publish();
    await expect.poll(() => boss.frames.length).toBe(2);
    await expect.poll(() => owner.frames.length).toBe(2);
    expect((await control(id, 'complete', 1, await state(id))).status).toBe(200);
    await expect.poll(() => boss.frames.length).toBe(3);
    await expect.poll(() => owner.frames.length).toBe(3);
    expect(other.frames).toEqual([{ kind: 'wall.changed' }]);
  } finally { boss.socket.close(); owner.socket.close(); other.socket.close(); }
});

it('rejects unauthenticated and cross-boss wall tickets', async () => {
  const endpoint = 'https://test.local/api/panel-wall-connections';
  expect((await SELF.fetch(endpoint, { method: 'POST' })).status).toBe(401);
  for (const headers of [authHeaders(), bossHeaders]) {
    const response = await SELF.fetch(endpoint, {
      method: 'POST', headers, body: JSON.stringify({ targetBossId: 'unrelated-boss' }),
    });
    expect(response.status).toBe(403);
  }
});

it.each(['fail', 'cancel'])('signals %s without a tile subscription', async action => {
  const boss = await wall(bossHeaders);
  try {
    const id = await publish();
    await expect.poll(() => boss.frames.length).toBe(2);
    const response = await SELF.fetch(`https://test.local/api/panels/${id}/lifecycle`, {
      method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() },
      body: JSON.stringify({ protocolVersion: 2, action, expectedMetadataVersion: 1, expectedDefinitionRevision: 1,
        expectedEpoch: null, expectedState: null, openRequests: 'reject', result: { title: action, code: 'test' } }),
    });
    expect(response.status).toBe(200);
    await expect.poll(() => boss.frames.length).toBe(3);
  } finally { boss.socket.close(); }
});

it('signals restored visibility on renewal and durable expiry without polling D1', async () => {
  const boss = await wall(bossHeaders);
  const id = await publish();
  const producer = await connect(id);
  try {
    await expect.poll(() => boss.frames.length).toBe(2);
    const row = await env.DB.prepare('SELECT lifecycle_json FROM panels WHERE panel_id = ?')
      .bind(id).first<{ lifecycle_json: string }>();
    if (!row) throw new Error('Missing panel');
    const lifecycle = JSON.parse(row.lifecycle_json) as Record<string, unknown>;
    lifecycle.expiresAt = new Date(Date.now() - 1).toISOString();
    await env.DB.prepare('UPDATE panels SET lifecycle_json = ? WHERE panel_id = ?')
      .bind(JSON.stringify(lifecycle), id).run();
    const response = await SELF.fetch(`https://test.local/api/panels/${id}/renew`, {
      method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() },
      body: JSON.stringify({ protocolVersion: 2, expectedMetadataVersion: 1, expectedDefinitionRevision: 1, ttlSeconds: 120 }),
    });
    expect(response.status).toBe(200);
    const renewed = await response.json<{ expiresAt: string }>();
    await expect.poll(() => boss.frames.length).toBe(3);
    expect(await producer.next('panel.changed')).toMatchObject({ metadataVersion: 2 });
    if (!env.PANEL_ROOM) throw new Error('Missing PanelRoom');
    const room = env.PANEL_ROOM.get(env.PANEL_ROOM.idFromName(bossId)) as DurableObjectStub<PanelRoom>;
    await runInDurableObject(room, async (instance, context) => {
      const expiry = await context.storage.get<{ expiresAt: number }>(`wall-expiry:${id}`);
      expect(expiry?.expiresAt).toBe(Date.parse(renewed.expiresAt));
      await context.storage.put(`wall-expiry:${id}`,
        { agentId: getTestAgentId(), expiresAt: Date.now() - 1 });
      await instance.alarm();
      expect(await context.storage.get(`wall-expiry:${id}`)).toBeUndefined();
    });
    await expect.poll(() => boss.frames.length).toBe(4);
  } finally { producer.socket.close(); boss.socket.close(); }
});

it('renews an active visibility deadline without invalidating the wall or tile metadata', async () => {
  const boss = await wall(bossHeaders);
  const owner = await wall(authHeaders());
  const id = await publish({ mode: 'monitor', expectedUpdateIntervalSeconds: 5, ttlSeconds: 60 });
  const producer = await connect(id);
  try {
    await expect.poll(() => boss.frames.length).toBe(2);
    await expect.poll(() => owner.frames.length).toBe(2);
    const before = await state(id);
    const response = await SELF.fetch(`https://test.local/api/panels/${id}/renew`, {
      method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': crypto.randomUUID() },
      body: JSON.stringify({ protocolVersion: 2, expectedMetadataVersion: 1,
        expectedDefinitionRevision: 1, ttlSeconds: 120 }),
    });
    expect(response.status).toBe(200);
    const renewed = await response.json<{ expiresAt: string }>();
    expect(await producer.next('state.observation')).toMatchObject({ expiresAt: renewed.expiresAt,
      sequence: before.sequence, observationVersion: before.observationVersion, task: before.task });
    expect(producer.frames.filter(frame => frame.kind === 'panel.changed')).toEqual([]);
    expect(boss.frames).toHaveLength(2);
    expect(owner.frames).toHaveLength(2);
    if (!env.PANEL_ROOM) throw new Error('Missing PanelRoom');
    const room = env.PANEL_ROOM.get(env.PANEL_ROOM.idFromName(bossId)) as DurableObjectStub<PanelRoom>;
    await runInDurableObject(room, async (instance, context) => {
      const expiry = await context.storage.get<{ expiresAt: number }>(`wall-expiry:${id}`);
      expect(expiry?.expiresAt).toBe(Date.parse(renewed.expiresAt));
      await instance.alarm();
      expect(await context.storage.get(`wall-expiry:${id}`)).toEqual(expiry);
      await context.storage.put(`wall-expiry:${id}`,
        { agentId: getTestAgentId(), expiresAt: Date.now() - 1 });
      await instance.alarm();
    });
    await expect.poll(() => boss.frames.length).toBe(3);
    await expect.poll(() => owner.frames.length).toBe(3);
  } finally { producer.socket.close(); boss.socket.close(); owner.socket.close(); }
});

it('keeps data updates, unchanged observations, and lease renewals off the wall', async () => {
  const boss = await wall(bossHeaders);
  const id = await publish();
  const producer = await connect(id);
  try {
    await expect.poll(() => boss.frames.length).toBe(2);
    const epoch = await claim(producer);
    producer.send({ kind: 'state.update', epoch, updateId: 'wall-data', baseSequence: 0,
      ops: [{ op: 'replace', path: '/task/done', value: 9 }] });
    expect(await producer.next('state.ack')).toMatchObject({ sequence: 1, observationVersion: 1 });
    const observed = producer.frames.length;
    producer.send({ kind: 'state.unchanged', epoch, updateId: 'wall-observation', baseSequence: 1 });
    expect(await producer.next('state.ack', observed)).toMatchObject({ sequence: 1, observationVersion: 2 });
    const renewed = producer.frames.length;
    producer.send({ kind: 'lease.renew', epoch });
    expect(await producer.next('state.observation', renewed))
      .toMatchObject({ sequence: 1, observationVersion: 2 });
    expect(producer.frames.filter(frame => frame.kind === 'panel.changed')).toEqual([]);
    expect(boss.frames).toHaveLength(2);
    expect((await control(id, 'pause', 1, await state(id))).status).toBe(200);
    await expect.poll(() => boss.frames.length).toBe(3);
    expect((await control(id, 'resume', 2, await state(id))).status).toBe(200);
    await expect.poll(() => boss.frames.length).toBe(4);
  } finally { producer.socket.close(); boss.socket.close(); }
});
