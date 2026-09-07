// Worker-pool integration tests for panel connection tickets and relay scope.
// Covers single-use/expiry, role permissions, tenant separation, and header transport.
// Dependencies: cloudflare:test, Hono worker, D1 seed helpers, and PanelRoom.

import { env, SELF } from 'cloudflare:test';
import { beforeAll, describe, expect, it } from 'vitest';
import { hashApiKey } from '../../middleware/auth';
import { seedBossToken, seedDatabase } from '../../test-helpers';

const OWNER_ID = 'relay-auth-owner';
const OWNER_KEY = 'hb_relay_auth_owner_0000000000000001';
const OTHER_AGENT_ID = 'relay-auth-other-agent';
const OTHER_AGENT_KEY = 'hb_relay_auth_other_agent_0000000000000001';
const BOSS_ID = 'relay-auth-boss';
const BOSS_TOKEN = 'hb_relay_auth_boss_0000000000000001';
const OTHER_BOSS_ID = 'relay-auth-other-boss';
const OTHER_BOSS_TOKEN = 'hb_relay_auth_other_boss_000000000001';
const PANEL_A = 'panel_relay_auth_a';
const PANEL_B = 'panel_relay_auth_b';
const PANEL_OTHER = 'panel_relay_auth_other';

type TicketResponse = { ticket: string; roomId: string; role: string; operations: string[]; expiresAt: number };
type RelayMessage = { kind: string; code?: string; sequence?: number };

function authHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}

async function seedPanel(panelId: string, agentId = OWNER_ID, bossId = BOSS_ID): Promise<void> {
  await env.DB.prepare("INSERT OR IGNORE INTO sessions (id, agent_id, label) VALUES (?, ?, 'relay auth')")
    .bind(`${panelId}-session`, agentId).run();
  await env.DB.prepare("INSERT OR IGNORE INTO panels (panel_id, agent_id, target_boss_id, task_key, session_id, title, catalog_id, catalog_version, summary_json, idempotency_key, request_hash, created_at) VALUES (?, ?, ?, 'relay-auth', ?, 'Relay auth', 'hiboss.panel', 1, '{}', ?, 'relay-auth-hash', datetime('now'))")
    .bind(panelId, agentId, bossId, `${panelId}-session`, `${panelId}-key`).run();
}

async function requestTicket(token: string, panelId: string, role: 'producer' | 'subscriber'): Promise<Response> {
  return SELF.fetch('https://test.local/api/panel-connections', {
    method: 'POST', headers: authHeaders(token), body: JSON.stringify({ panelId, role }),
  });
}

async function connect(ticket: string): Promise<{ ws: WebSocket; messages: RelayMessage[] }> {
  const messages: RelayMessage[] = [];
  const response = await SELF.fetch('https://test.local/api/panel-relay', {
    headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket },
  });
  const ws = response.webSocket;
  if (!ws) throw new Error(`websocket upgrade failed: ${response.status}`);
  ws.accept();
  ws.addEventListener('message', (event) => messages.push(JSON.parse(event.data as string) as RelayMessage));
  return { ws, messages };
}

async function waitForMessage(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 50));
}

function ticketForRoom(ticket: string, roomId: string): string {
  const bytes = Uint8Array.from(atob(ticket.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - (ticket.length % 4)) % 4)), (char) => char.charCodeAt(0));
  const envelope = JSON.parse(new TextDecoder().decode(bytes)) as { roomId: string; ticketId: string; secret: string };
  envelope.roomId = roomId;
  const encoded = new TextEncoder().encode(JSON.stringify(envelope));
  let binary = '';
  for (const byte of encoded) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(OWNER_ID, 'relay auth owner', await hashApiKey(OWNER_KEY)).run();
  await env.DB.prepare('INSERT OR IGNORE INTO api_keys (id, name, key_hash) VALUES (?, ?, ?)')
    .bind(OTHER_AGENT_ID, 'relay auth other agent', await hashApiKey(OTHER_AGENT_KEY)).run();
  await seedBossToken('Relay auth boss', 'viewer', BOSS_TOKEN, BOSS_ID);
  await seedBossToken('Relay auth other boss', 'viewer', OTHER_BOSS_TOKEN, OTHER_BOSS_ID);
  await env.DB.prepare('INSERT OR IGNORE INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(BOSS_ID, OWNER_ID).run();
  await seedPanel(PANEL_A);
  await seedPanel(PANEL_B);
  await seedPanel(PANEL_OTHER, OTHER_AGENT_ID);
});

describe('panel connection authorization', () => {
  it('issues a ticket that upgrades once and refuses its second use', async () => {
    const response = await requestTicket(OWNER_KEY, PANEL_A, 'producer');
    expect(response.status).toBe(201);
    const ticket = await response.json() as TicketResponse;
    expect(ticket.roomId).toBe(BOSS_ID);
    expect(ticket.role).toBe('producer');
    expect(ticket.operations).toEqual(['subscribe', 'lease.claim', 'state.update']);
    expect(ticket.expiresAt).toBeGreaterThan(Date.now() + 59_000);
    const first = await connect(ticket.ticket);
    const second = await SELF.fetch('https://test.local/api/panel-relay', {
      headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket.ticket },
    });
    expect(second.status).toBe(401);
    first.ws.close();
  });

  it('refuses an expired ticket before the WebSocket upgrade', async () => {
    const room = env.PANEL_ROOM!.get(env.PANEL_ROOM!.idFromName(BOSS_ID));
    const issued = await room.fetch(new Request('https://panel-room.internal/__issue-ticket', {
      method: 'POST', body: JSON.stringify({ roomId: BOSS_ID, identity: OWNER_ID, role: 'producer', panelId: PANEL_A, operations: ['subscribe', 'lease.claim', 'state.update'], expiresAt: Date.now() + 1_000 }),
    }));
    const ticket = await issued.json() as TicketResponse;
    await new Promise((resolve) => setTimeout(resolve, 1_100));
    const response = await SELF.fetch('https://test.local/api/panel-relay', {
      headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticket.ticket },
    });
    expect(response.status).toBe(410);
  });

  it('refuses a ticket whose room scope was changed before the WebSocket upgrade', async () => {
    const response = await requestTicket(OWNER_KEY, PANEL_A, 'producer');
    const ticket = await response.json() as TicketResponse;
    const responseForWrongRoom = await SELF.fetch('https://test.local/api/panel-relay', {
      headers: { Upgrade: 'websocket', 'X-Panel-Connection-Ticket': ticketForRoom(ticket.ticket, OTHER_BOSS_ID) },
    });
    expect(responseForWrongRoom.status).toBe(401);
  });

  it('keeps subscriber tickets from claiming leases and producer tickets from writing another panel', async () => {
    const subscriberTicket = await (await requestTicket(BOSS_TOKEN, PANEL_A, 'subscriber')).json() as TicketResponse;
    const subscriber = await connect(subscriberTicket.ticket);
    subscriber.ws.send(JSON.stringify({ kind: 'subscribe', panelId: PANEL_A }));
    await waitForMessage();
    subscriber.ws.send(JSON.stringify({ kind: 'lease.claim', panelId: PANEL_A, epoch: 'boss-must-not-claim' }));
    await waitForMessage();
    expect(subscriber.messages.some((message) => message.code === 'permission_denied')).toBe(true);

    const producerTicket = await (await requestTicket(OWNER_KEY, PANEL_A, 'producer')).json() as TicketResponse;
    const producer = await connect(producerTicket.ticket);
    producer.ws.send(JSON.stringify({ kind: 'subscribe', panelId: PANEL_A }));
    await waitForMessage();
    producer.ws.send(JSON.stringify({ kind: 'state.update', panelId: PANEL_B, epoch: 'wrong-panel', baseSequence: 0, ops: [] }));
    await waitForMessage();
    expect(producer.messages.some((message) => message.code === 'permission_denied')).toBe(true);
    subscriber.ws.close();
    producer.ws.close();
  });

  it('refuses a boss with no relationship to the panel', async () => {
    const response = await requestTicket(OTHER_BOSS_TOKEN, PANEL_A, 'subscriber');
    expect(response.status).toBe(404);
  });

  it('does not let one agent request another agent producer ticket', async () => {
    const denied = await requestTicket(OWNER_KEY, PANEL_OTHER, 'producer');
    expect(denied.status).toBe(404);
    const owner = await requestTicket(OTHER_AGENT_KEY, PANEL_OTHER, 'producer');
    expect(owner.status).toBe(201);
  });

  it('uses a handshake header while the relay URL contains no credential', async () => {
    const response = await requestTicket(OWNER_KEY, PANEL_A, 'producer');
    const ticket = await response.json() as TicketResponse;
    const relayUrl = 'https://test.local/api/panel-relay';
    expect(relayUrl).not.toContain(ticket.ticket);
    const queryAttempt = await SELF.fetch(`${relayUrl}?ticket=${encodeURIComponent(ticket.ticket)}`, { headers: { Upgrade: 'websocket' } });
    expect(queryAttempt.status).toBe(401);
    const connection = await connect(ticket.ticket);
    expect(connection.ws).toBeDefined();
    connection.ws.close();
  });
});
