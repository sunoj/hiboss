// Sequential archive regressions through real Worker routes and DO WebSockets.
// Covers cross-boss admin subscriptions, wall sockets, and manager/viewer eviction.
// Dependencies: Cloudflare test runtime and authenticated relay fixtures.
import { env, SELF, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { Hono } from 'hono';
import { archiveBoss } from '../../routes/boss-archive';
import { bossAuth } from '../../middleware/auth';
import type { Env } from '../../types';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, seedBossToken } from '../../test-helpers';
import { bossHeaders, bossId, claim, connect, publish, seed } from './runtime/test-support';

const archiver = { Authorization: 'Bearer relay-archiver', 'Content-Type': 'application/json' };
const admin = { Authorization: 'Bearer relay-archived-admin', 'Content-Type': 'application/json' };
const adminId = 'relay-archived-admin';

beforeAll(async () => {
  await seed();
  await seedBossToken('Archiver', 'admin', 'relay-archiver', 'relay-archiver');
  await seedBossToken('Subscriber admin', 'admin', 'relay-archived-admin', adminId);
});

async function subscribe(panelId: string, headers: Record<string, string>, wallBoss?: string) {
  const response = await SELF.fetch(`https://test.local/api/${wallBoss ? 'panel-wall-connections' : 'panel-connections'}`, {
    method: 'POST', headers, body: JSON.stringify(wallBoss ? { targetBossId: wallBoss } : { panelId, role: 'subscriber' }),
  });
  expect(response.status).toBe(201);
  const { ticket } = await response.json<{ ticket: string }>();
  const upgraded = await SELF.fetch('https://test.local/api/panel-relay', { headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket } });
  const socket = upgraded.webSocket;
  if (!socket) throw new Error('Missing WebSocket');
  socket.accept();
  const frames: unknown[] = [];
  const closed: { code: number; reason: string }[] = [];
  socket.addEventListener('message', event => { frames.push(JSON.parse(String(event.data))); });
  socket.addEventListener('close', event => { closed.push({ code: event.code, reason: event.reason }); });
  socket.send(JSON.stringify({ protocolVersion: 2, panelId, kind: wallBoss ? 'wall.subscribe' : 'subscribe' }));
  await expect.poll(() => frames.length).toBe(1);
  return { socket, frames, closed };
}

function change(id: string, action = 'archive'): Promise<Response> {
  return SELF.fetch(`https://test.local/api/bosses/${id}/${action}`, { method: 'POST', headers: archiver });
}

it('closes an archived admin subscriber before the next producer patch and preserves other sockets', async () => {
  const id = await publish();
  const producer = await connect(id); const epoch = await claim(producer);
  const survivor = await connect(id, true);
  const subscriber = await subscribe(id, admin);
  const wall = await subscribe('wall', admin, adminId);
  const ownerWall = await subscribe('wall', authHeaders(), adminId);
  try {
    const before = [...subscriber.frames]; const wallBefore = [...wall.frames];
    expect((await change(adminId)).status).toBe(200);
    producer.send({ kind: 'state.update', epoch, updateId: 'after-archive', baseSequence: 0,
      ops: [{ op: 'replace', path: '/task/done', value: 9 }] });
    await producer.next('state.ack'); await survivor.next('state.patch');
    expect(subscriber.frames).toEqual(before);
    await expect.poll(() => subscriber.closed).toEqual([{ code: 4401, reason: 'boss archived' }]);
    await expect.poll(() => wall.closed).toEqual([{ code: 4401, reason: 'boss archived' }]);
    if (!env.PANEL_ROOM) throw new Error('Missing PanelRoom');
    const room = env.PANEL_ROOM.get(env.PANEL_ROOM.idFromName(adminId));
    expect((await room.fetch('https://panel-room.internal/__wall-changed', { method: 'POST', body: JSON.stringify({
      panelId: id, agentId: 'test-agent-id', expiresAt: new Date(Date.now() + 60_000).toISOString(),
    }) })).status).toBe(204);
    await expect.poll(() => ownerWall.frames.length).toBe(2);
    expect(wall.frames).toEqual(wallBefore);
    expect(ownerWall.closed).toEqual([]);
  } finally {
    for (const connection of [producer, survivor, subscriber, wall, ownerWall]) connection.socket.close();
  }
});

it.each(['manager', 'viewer'])('closes an archived %s subscription in its target room', async role => {
  await env.DB.prepare('UPDATE bosses SET role = ? WHERE id = ?').bind(role, bossId).run();
  const id = await publish();
  const subscriber = await subscribe(id, bossHeaders);
  try {
    expect((await change(bossId)).status).toBe(200);
    await expect.poll(() => subscriber.closed).toEqual([{ code: 4401, reason: 'boss archived' }]);
    expect(subscriber.frames).toHaveLength(1);
    expect((await change(bossId, 'restore')).status).toBe(200);
    const restored = await subscribe(id, bossHeaders);
    restored.socket.close();
  } finally {
    subscriber.socket.close();
    await env.DB.prepare("UPDATE bosses SET archived_at = NULL, role = 'manager' WHERE id = ?").bind(bossId).run();
  }
});

it('rejects malformed internal eviction requests without closing a valid subscriber', async () => {
  const id = await publish(); const subscriber = await subscribe(id, bossHeaders);
  if (!env.PANEL_ROOM) throw new Error('Missing PanelRoom');
  const room = env.PANEL_ROOM.get(env.PANEL_ROOM.idFromName(bossId));
  try {
    for (const body of ['{', '{}', '{"identity":3}', '{"identity":""}']) {
      expect((await room.fetch('https://panel-room.internal/__evict-subscriber', { method: 'POST', body })).status).toBe(400);
    }
    expect(subscriber.closed).toEqual([]);
  } finally { subscriber.socket.close(); }
});

it('attempts every relevant room and retains the archive when a room is unavailable', async () => {
  expect((await change(adminId, 'restore')).status).toBe(200);
  await seedBossToken('Ended panel owner', 'manager', 'ended-owner', 'ended-owner');
  await seedBossToken('Paused panel owner', 'manager', 'paused-owner', 'paused-owner');
  const ended = await publish(); const paused = await publish();
  await env.DB.prepare("UPDATE panels SET target_boss_id = 'ended-owner', lifecycle_json = json_set(lifecycle_json, '$.taskState', 'completed') WHERE panel_id = ?").bind(ended).run();
  await env.DB.prepare("UPDATE panels SET target_boss_id = 'paused-owner', lifecycle_json = json_set(lifecycle_json, '$.taskState', 'paused') WHERE panel_id = ?").bind(paused).run();
  const visited: string[] = [];
  const requests: { url: string; body: unknown }[] = [];
  const namespace = {
    idFromName: (id: string) => id,
    get: (id: string) => ({ fetch: async (url: string, request: RequestInit) => {
      visited.push(id);
      requests.push({ url, body: JSON.parse(String(request.body)) });
      if (id === adminId) throw new Error('wall unavailable');
      return new Response(null, { status: 204 });
    } }),
  } as unknown as NonNullable<Env['PANEL_ROOM']>;
  const app = new Hono<{ Bindings: Env }>();
  app.post('/:id/archive', bossAuth, archiveBoss);
  const context = createExecutionContext();
  const response = await app.fetch(new Request(`https://test.local/${adminId}/archive`, { method: 'POST', headers: archiver }), { ...env, PANEL_ROOM: namespace }, context);
  await waitOnExecutionContext(context);
  expect(response.status).toBe(200);
  expect((await response.json<{ archived_at: string }>()).archived_at).toEqual(expect.any(String));
  expect(visited.sort()).toEqual([adminId, bossId, 'paused-owner'].sort());
  expect(requests).toEqual(Array.from({ length: 3 }, () => ({
    url: 'https://panel-room.internal/__evict-subscriber', body: { identity: adminId },
  })));
});
