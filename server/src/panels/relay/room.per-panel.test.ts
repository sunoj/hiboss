// Purpose: Regression tests for per-panel relay snapshots, leases, and sequences.
// Exports: none
// Dependencies: cloudflare:test, vitest, and relay database seed helpers.

import { env } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { seedDatabase } from '../../test-helpers';

type RelayMessage = {
  kind: string;
  code?: string;
  epoch?: string;
  sequence?: number;
  task?: Record<string, unknown>;
};

type RelayConnection = { ws: WebSocket; messages: RelayMessage[] };

const RELAY_AGENT = 'relay-per-panel-agent';

async function seedPanel(roomId: string, panelId: string): Promise<void> {
  await seedDatabase();
  await env.DB.prepare("INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, 'relay per-panel agent', 'relay-per-panel-hash')").bind(RELAY_AGENT).run();
  await env.DB.prepare("INSERT OR IGNORE INTO bosses (id, name, role) VALUES (?, 'Relay per-panel boss', 'viewer')").bind(roomId).run();
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(roomId, RELAY_AGENT).run();
  await env.DB.prepare("INSERT OR IGNORE INTO sessions (id, agent_id, label) VALUES (?, ?, 'relay per-panel')").bind(`${panelId}-session`, RELAY_AGENT).run();
  await env.DB.prepare("INSERT OR IGNORE INTO panels (panel_id, agent_id, target_boss_id, task_key, session_id, title, catalog_id, catalog_version, summary_json, idempotency_key, request_hash, created_at) VALUES (?, ?, ?, 'relay-per-panel', ?, 'Relay per-panel', 'hiboss.panel', 1, '{}', ?, 'relay-per-panel-hash', datetime('now'))")
    .bind(panelId, RELAY_AGENT, roomId, `${panelId}-session`, `${panelId}-key`).run();
}

async function issueTicket(stub: DurableObjectStub, roomId: string, panelId: string, role: 'producer' | 'subscriber'): Promise<string> {
  const response = await stub.fetch(new Request('https://panel-room.internal/__issue-ticket', {
    method: 'POST',
    body: JSON.stringify({ roomId, identity: role === 'producer' ? RELAY_AGENT : roomId, role, panelId, operations: role === 'producer' ? ['subscribe', 'lease.claim', 'state.update'] : ['subscribe'], expiresAt: Date.now() + 60_000 }),
  }));
  const body = await response.json() as { ticket: string };
  return body.ticket;
}

async function connect(stub: DurableObjectStub, roomId: string, panelId: string, role: 'producer' | 'subscriber' = 'producer'): Promise<RelayConnection> {
  const ticket = await issueTicket(stub, roomId, panelId, role);
  const response = await stub.fetch(new Request('http://localhost/', {
    headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket },
  }));
  const ws = response.webSocket;
  if (!ws) throw new Error('No websocket');
  ws.accept();
  const messages: RelayMessage[] = [];
  ws.addEventListener('message', (event) => messages.push(JSON.parse(event.data as string) as RelayMessage));
  ws.send(JSON.stringify({ kind: 'subscribe', panelId }));
  await waitForRelay();
  return { ws, messages };
}

async function waitForRelay(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 50));
}

function claim(ws: WebSocket, panelId: string, epoch: string): void {
  ws.send(JSON.stringify({ kind: 'lease.claim', panelId, epoch }));
}

function update(ws: WebSocket, panelId: string, epoch: string, baseSequence: number, value: string): void {
  ws.send(JSON.stringify({
    kind: 'state.update', panelId, epoch, baseSequence,
    ops: [{ op: 'add', path: '/task/value', value }],
  }));
}

function hasAck(messages: RelayMessage[], sequence: number): boolean {
  return messages.some((message) => message.kind === 'state.ack' && message.sequence === sequence);
}

describe('PanelRoom per-panel persistence', () => {
  beforeAll(async () => { await seedDatabase(); });

  it('keeps two panels independent when either panel is written', async () => {
    const roomId = 'per-panel-state';
    const panelA = `${roomId}-a`;
    const panelB = `${roomId}-b`;
    await seedPanel(roomId, panelA);
    await seedPanel(roomId, panelB);
    const stub = env.PANEL_ROOM!.get(env.PANEL_ROOM!.idFromName(roomId));
    const producerA = await connect(stub, roomId, panelA);
    const producerB = await connect(stub, roomId, panelB);
    claim(producerA.ws, panelA, 'epoch-a');
    claim(producerB.ws, panelB, 'epoch-b');
    await waitForRelay();
    update(producerA.ws, panelA, 'epoch-a', 0, 'A');
    update(producerB.ws, panelB, 'epoch-b', 0, 'B');
    await waitForRelay();
    expect(hasAck(producerA.messages, 1)).toBe(true);
    expect(hasAck(producerB.messages, 1)).toBe(true);
    producerA.ws.close();
    producerB.ws.close();
    const subscriberA = await connect(stub, roomId, panelA, 'subscriber');
    const subscriberB = await connect(stub, roomId, panelB, 'subscriber');
    expect(subscriberA.messages[0]).toMatchObject({ kind: 'state.snapshot', sequence: 1, task: { value: 'A' } });
    expect(subscriberB.messages[0]).toMatchObject({ kind: 'state.snapshot', sequence: 1, task: { value: 'B' } });
    subscriberA.ws.close();
    subscriberB.ws.close();
  });

  it('lets producers write panel B while panel A holds its lease', async () => {
    const roomId = 'per-panel-leases';
    const panelA = `${roomId}-a`;
    const panelB = `${roomId}-b`;
    await seedPanel(roomId, panelA);
    await seedPanel(roomId, panelB);
    const stub = env.PANEL_ROOM!.get(env.PANEL_ROOM!.idFromName(roomId));
    const producerA = await connect(stub, roomId, panelA);
    const producerB = await connect(stub, roomId, panelB);
    claim(producerA.ws, panelA, 'epoch-a');
    await waitForRelay();
    claim(producerB.ws, panelB, 'epoch-b');
    await waitForRelay();
    update(producerA.ws, panelA, 'epoch-a', 0, 'A');
    update(producerB.ws, panelB, 'epoch-b', 0, 'B');
    await waitForRelay();
    expect(hasAck(producerA.messages, 1)).toBe(true);
    expect(hasAck(producerB.messages, 1)).toBe(true);
    producerA.ws.close();
    producerB.ws.close();
  });

  it('fences panel A without replacing panel B lease', async () => {
    const roomId = 'per-panel-fencing';
    const panelA = `${roomId}-a`;
    const panelB = `${roomId}-b`;
    await seedPanel(roomId, panelA);
    await seedPanel(roomId, panelB);
    const stub = env.PANEL_ROOM!.get(env.PANEL_ROOM!.idFromName(roomId));
    const producerA = await connect(stub, roomId, panelA);
    const producerB = await connect(stub, roomId, panelB);
    claim(producerA.ws, panelA, 'epoch-a-old');
    claim(producerB.ws, panelB, 'epoch-b');
    await waitForRelay();
    claim(producerA.ws, panelA, 'epoch-a-new');
    await waitForRelay();
    update(producerB.ws, panelB, 'epoch-b', 0, 'B');
    await waitForRelay();
    expect(hasAck(producerB.messages, 1)).toBe(true);
    producerA.ws.close();
    producerB.ws.close();
  });

  it('sends a subscriber the snapshot for its panel', async () => {
    const roomId = 'per-panel-subscription';
    const panelA = `${roomId}-a`;
    const panelB = `${roomId}-b`;
    await seedPanel(roomId, panelA);
    await seedPanel(roomId, panelB);
    const stub = env.PANEL_ROOM!.get(env.PANEL_ROOM!.idFromName(roomId));
    const producerA = await connect(stub, roomId, panelA);
    claim(producerA.ws, panelA, 'epoch-a');
    await waitForRelay();
    update(producerA.ws, panelA, 'epoch-a', 0, 'A');
    await waitForRelay();
    const producerB = await connect(stub, roomId, panelB);
    claim(producerB.ws, panelB, 'epoch-b');
    await waitForRelay();
    update(producerB.ws, panelB, 'epoch-b', 1, 'B');
    await waitForRelay();
    const subscriberA = await connect(stub, roomId, panelA, 'subscriber');
    expect(subscriberA.messages[0]).toMatchObject({ kind: 'state.snapshot', sequence: 1, task: { value: 'A' } });
    producerA.ws.close();
    producerB.ws.close();
    subscriberA.ws.close();
  });

  it('advances sequence numbers independently for each panel', async () => {
    const roomId = 'per-panel-sequences';
    const panelA = `${roomId}-a`;
    const panelB = `${roomId}-b`;
    await seedPanel(roomId, panelA);
    await seedPanel(roomId, panelB);
    const stub = env.PANEL_ROOM!.get(env.PANEL_ROOM!.idFromName(roomId));
    const producerA = await connect(stub, roomId, panelA);
    const producerB = await connect(stub, roomId, panelB);
    claim(producerA.ws, panelA, 'shared-test-epoch');
    claim(producerB.ws, panelB, 'shared-test-epoch');
    await waitForRelay();
    update(producerA.ws, panelA, 'shared-test-epoch', 0, 'A');
    update(producerB.ws, panelB, 'shared-test-epoch', 0, 'B');
    await waitForRelay();
    expect(hasAck(producerA.messages, 1)).toBe(true);
    expect(hasAck(producerB.messages, 1)).toBe(true);
    producerA.ws.close();
    producerB.ws.close();
  });
});
