// Live panel subscriptions end with the credential and access that opened them.
// Covers role demotion, grant loss, token revocation and a failed access check against real DO WebSockets.
// Dependencies: Cloudflare test runtime and the relay lifecycle harness.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { hashApiKey } from '../../middleware/auth';
import { getTestAgentId, seedBossToken } from '../../test-helpers';
import { bossHeaders, bossId, claim, connect, publish, seed } from './runtime/test-support';

const api = 'https://test.local/api';
const unique = (name: string): string => `lp1-${name}-${crypto.randomUUID().slice(0, 8)}`;
const headers = (token: string): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
const root = { id: 'lp1-root-admin', token: 'hb_lp1_root_admin_token' };

beforeAll(async () => {
  await seed();
  await seedBossToken('LP1 root', 'admin', root.token, root.id);
});

async function boss(role: string, granted = false): Promise<{ id: string; token: string }> {
  const id = unique(role);
  const token = `hb_${id}`;
  await seedBossToken(id, role, token, id);
  if (granted) await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(id, getTestAgentId()).run();
  return { id, token };
}

async function open(panelId: string, token: string, wall?: string) {
  const response = await SELF.fetch(`${api}/${wall ? 'panel-wall-connections' : 'panel-connections'}`, {
    method: 'POST', headers: headers(token), body: JSON.stringify(wall ? { targetBossId: wall } : { panelId, role: 'subscriber' }),
  });
  expect(response.status).toBe(201);
  const { ticket } = await response.json<{ ticket: string }>();
  const upgraded = await SELF.fetch(`${api}/panel-relay`, { headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket } });
  const socket = upgraded.webSocket;
  if (!socket) throw new Error('Missing WebSocket');
  socket.accept();
  const frames: Array<{ kind: string }> = [];
  const closed: number[] = [];
  socket.addEventListener('message', event => { frames.push(JSON.parse(String(event.data)) as { kind: string }); });
  socket.addEventListener('close', event => { closed.push(event.code); });
  const subscribe = () => socket.send(JSON.stringify({ protocolVersion: 2, panelId, kind: wall ? 'wall.subscribe' : 'subscribe' }));
  return { socket, frames, closed, subscribe };
}

async function subscribe(panelId: string, token: string, wall?: string) {
  const connection = await open(panelId, token, wall);
  connection.subscribe();
  await expect.poll(() => connection.frames.length).toBe(1);
  return connection;
}

/** Publishes, subscribes, applies `change`, then sends one producer patch; returns the subscriber's view. */
async function afterChange(token: string, change: () => Promise<void>) {
  const id = await publish();
  const producer = await connect(id);
  const epoch = await claim(producer);
  const survivor = await connect(id, true);
  const subscriber = await subscribe(id, token);
  try {
    const patch = async (value: number) => {
      const start = survivor.frames.length;
      const acked = producer.frames.length;
      producer.send({ kind: 'state.update', epoch, updateId: crypto.randomUUID(), baseSequence: value,
        ops: [{ op: 'replace', path: '/task/done', value: value + 1 }] });
      await producer.next('state.ack', acked);
      await survivor.next('state.patch', start);
    };
    await patch(0);
    await expect.poll(() => subscriber.frames.filter(f => f.kind === 'state.patch').length).toBe(1);
    await change();
    await patch(1);
    await expect.poll(() => subscriber.closed).toEqual([4401]);
    return subscriber.frames.filter(f => f.kind === 'state.patch').length;
  } finally {
    for (const socket of [producer.socket, survivor.socket, subscriber.socket]) socket.close();
  }
}

it('LP-1 demoting a non-target admin stops its subscription before the next patch', async () => {
  const watcher = await boss('admin');
  const patches = await afterChange(watcher.token, async () => {
    const response = await SELF.fetch(`${api}/bosses/${watcher.id}`, { method: 'PATCH', headers: headers(root.token), body: JSON.stringify({ role: 'manager' }) });
    expect(response.status).toBe(200);
  });
  expect(patches).toBe(1);
});

it('LP-1 revoking the subscriber token stops its subscription before the next patch', async () => {
  const watcher = await boss('admin');
  const patches = await afterChange(watcher.token, async () => {
    const row = await env.DB.prepare('SELECT id FROM boss_tokens WHERE token_hash = ?').bind(await hashApiKey(watcher.token)).first<{ id: string }>();
    const response = await SELF.fetch(`${api}/boss/tokens/${row?.id}`, { method: 'DELETE', headers: headers(watcher.token) });
    expect(response.status).toBe(200);
  });
  expect(patches).toBe(1);
});

it('LP-1 rotating the subscriber boss closes its own wall socket on the next signal', async () => {
  const owner = await boss('manager', true);
  const wall = await subscribe('wall', owner.token, owner.id);
  try {
    expect((await SELF.fetch(`${api}/bosses/${owner.id}/token`, { method: 'POST', headers: headers(root.token) })).status).toBe(200);
    if (!env.PANEL_ROOM) throw new Error('Missing PanelRoom');
    const room = env.PANEL_ROOM.get(env.PANEL_ROOM.idFromName(owner.id));
    expect((await room.fetch('https://panel-room.internal/__wall-changed', { method: 'POST', body: JSON.stringify({
      panelId: 'lp1-wall', agentId: getTestAgentId(), expiresAt: new Date(Date.now() + 60_000).toISOString(),
    }) })).status).toBe(204);
    await expect.poll(() => wall.closed).toEqual([4401]);
    expect(wall.frames).toHaveLength(1);
  } finally { wall.socket.close(); }
});

it('LP-1 a target boss that loses its grant gets no further frames and is closed on resubscribe', async () => {
  const id = await publish();
  const producer = await connect(id);
  const epoch = await claim(producer);
  const subscriber = await subscribe(id, bossHeaders.Authorization.slice(7));
  const revoke = await SELF.fetch(`${api}/bosses/${bossId}/access/${getTestAgentId()}`, { method: 'DELETE', headers: headers(root.token) });
  try {
    expect(revoke.status).toBe(200);
    const start = producer.frames.length;
    producer.send({ kind: 'state.update', epoch, updateId: crypto.randomUUID(), baseSequence: 0,
      ops: [{ op: 'replace', path: '/task/done', value: 1 }] });
    await producer.next('error', start);
    subscriber.subscribe();
    await expect.poll(() => subscriber.closed).toEqual([4401]);
    expect(subscriber.frames.map(frame => frame.kind)).toEqual(['state.snapshot']);
  } finally {
    await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(bossId, getTestAgentId()).run();
    for (const socket of [producer.socket, subscriber.socket]) socket.close();
  }
});

it('LP-1 a failed access check closes a subscribing socket with 1013 so the client reconnects', async () => {
  const id = await publish();
  const watcher = await boss('admin');
  const connection = await open(id, watcher.token);
  // The gate's panel query reads boss_agent_access; without the table the check fails rather than denies.
  await env.DB.prepare('ALTER TABLE boss_agent_access RENAME TO boss_agent_access_hidden').run();
  try {
    connection.subscribe();
    await expect.poll(() => connection.closed).toEqual([1013]);
    expect(connection.frames).toEqual([]);
  } finally {
    await env.DB.prepare('ALTER TABLE boss_agent_access_hidden RENAME TO boss_agent_access').run();
    connection.socket.close();
  }
});
