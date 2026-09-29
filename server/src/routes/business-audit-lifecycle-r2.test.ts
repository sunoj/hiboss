// Round-two lifecycle regressions for session reuse and merged destination delivery.
// Covers stale replies, boss cascade deletion, and deletion during an active send.
// Depends on the Worker API, seeded D1, and the destination drain.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import { createAgent } from '../agent-keys';
import { drainDestinationDeliveries } from '../delivery/dispatch';
import { chatKey } from '../delivery/targets';
import * as adapters from '../delivery/adapters';
import { seedBossToken, seedDatabase, getTestAgentId } from '../test-helpers';
import type { Env, MessageRow } from '../types';

const api = 'https://test.local/api';
const unique = (name: string): string => `l2-${name}-${crypto.randomUUID().slice(0, 8)}`;
const headers = (token: string): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });
const on = (): Env => ({ ...env, DESTINATIONS_MODE: 'on' });

beforeAll(async () => { await seedDatabase(); });
afterEach(() => { vi.restoreAllMocks(); });

async function boss(name: string, role = 'admin'): Promise<{ id: string; token: string }> {
  const id = unique(name);
  const token = `hb_${id}`;
  await seedBossToken(id, role, token, id);
  return { id, token };
}

async function parentMessage(agentId: string, sessionId: string): Promise<string> {
  const id = unique('parent');
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, session_id)
    VALUES (?, ?, 'agent_to_boss', 'async', 'api', 'question', 'sent', ?)`).bind(id, agentId, sessionId).run();
  return id;
}

async function reply(token: string, parentId: string): Promise<Response> {
  return SELF.fetch(`${api}/boss/messages/${parentId}/reply`, {
    method: 'POST', headers: headers(token), body: JSON.stringify({ body: unique('reply') }),
  });
}

async function deliveryPair(name: string): Promise<{
  primaryBoss: { id: string; token: string }; primary: string; secondary: string; message: string;
}> {
  const primaryBoss = await boss(`${name}-primary`);
  const otherBoss = await boss(`${name}-secondary`);
  const prefix = unique(name);
  const primary = `${prefix}-a`;
  const secondary = `${prefix}-z`;
  const provider = unique('provider');
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES (?, 'telegram', ?, ?)")
    .bind(provider, provider, JSON.stringify({ bot_token: provider })).run();
  for (const [id, bossId] of [[primary, primaryBoss.id], [secondary, otherBoss.id]]) {
    await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label)
      VALUES (?, ?, 'telegram_chat', ?, ?, ?)`)
      .bind(id, bossId, provider, JSON.stringify({ chat_id: prefix }), id).run();
  }
  const row = await env.DB.prepare(`INSERT INTO messages (agent_id, direction, mode, channel, body, status)
    VALUES (?, 'agent_to_boss', 'async', 'telegram', 'delivery', 'sent') RETURNING *`)
    .bind(getTestAgentId()).first<MessageRow>();
  if (!row) throw new Error('message fixture failed');
  const first = `${prefix}-delivery-a`;
  await env.DB.prepare(`INSERT INTO message_deliveries
    (id, message_id, destination_id, external_target, next_attempt_at)
    VALUES (?, ?, ?, ?, '2000-01-01T00:00:00.000Z')`)
    .bind(first, row.id, primary, await chatKey('telegram', { chat_id: prefix, bot_token: provider })).run();
  await env.DB.prepare('INSERT INTO message_deliveries (message_id, destination_id, merged_into) VALUES (?, ?, ?)')
    .bind(row.id, secondary, first).run();
  return { primaryBoss, primary, secondary, message: row.id };
}

async function deliveryRows(message: string): Promise<{ destination_id: string; merged_into: string | null; status: string }[]> {
  const rows = await env.DB.prepare('SELECT destination_id, merged_into, status FROM message_deliveries WHERE message_id = ? ORDER BY destination_id')
    .bind(message).all<{ destination_id: string; merged_into: string | null; status: string }>();
  return rows.results;
}

it('R2 deleted session reply stores its message but cannot seed events for a new owner', async () => {
  const previous = await createAgent(env.DB, unique('previous'), { type: 'system', id: 'lifecycle-r2-test' });
  const next = await createAgent(env.DB, unique('next'), { type: 'system', id: 'lifecycle-r2-test' });
  if (!previous || !next) throw new Error('agent fixture failed');
  const manager = await boss('reply-manager', 'manager');
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(manager.id, previous.id).run();
  const session = unique('session');
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(session, previous.id).run();
  const controlParent = await parentMessage(previous.id, session);
  const staleParent = await parentMessage(previous.id, session);
  const control = await reply(manager.token, controlParent);
  expect(control.status).toBe(201);
  const eventsPath = `${api}/sessions/${session}/events`;
  const prior = await SELF.fetch(eventsPath, { headers: headers(previous.key) });
  expect((await prior.json() as { events: unknown[] }).events).toHaveLength(1);

  const deleted = await SELF.fetch(`${api}/sessions/${session}`, { method: 'DELETE', headers: headers(previous.key) });
  expect(deleted.status).toBe(200);
  const stale = await reply(manager.token, staleParent);
  expect(stale.status).toBe(201);
  const staleMessage = await stale.json() as { id: string };
  expect(await env.DB.prepare('SELECT id FROM messages WHERE id = ?').bind(staleMessage.id).first()).toEqual({ id: staleMessage.id });
  expect(await env.DB.prepare('SELECT id FROM session_events WHERE message_id = ?').bind(staleMessage.id).first()).toBeNull();
  const registered = await SELF.fetch(`${api}/sessions`, {
    method: 'POST', headers: headers(next.key), body: JSON.stringify({ id: session, project: unique('project') }),
  });
  expect(registered.status).toBe(201);
  const reused = await SELF.fetch(eventsPath, { headers: headers(next.key) });
  expect(reused.status).toBe(200);
  expect((await reused.json() as { events: unknown[] }).events).toEqual([]);
});

it('R2 deleting a primary boss promotes the surviving delivery and drains once', async () => {
  const send = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  const control = await deliveryPair('boss-control');
  expect((await deliveryRows(control.message)).map(row => row.merged_into === null)).toEqual([true, false]);
  await drainDestinationDeliveries(on());
  expect(send).toHaveBeenCalledTimes(1);
  expect((await deliveryRows(control.message)).map(row => row.status)).toEqual(['sent', 'sent']);

  send.mockClear();
  const target = await deliveryPair('boss-delete');
  const deleted = await SELF.fetch(`${api}/bosses/${target.primaryBoss.id}`, {
    method: 'DELETE', headers: headers(target.primaryBoss.token),
  });
  expect(deleted.status).toBe(200);
  expect(await deliveryRows(target.message)).toEqual([{ destination_id: target.secondary, merged_into: null, status: 'queued' }]);
  await drainDestinationDeliveries(on());
  await drainDestinationDeliveries(on());
  expect(send).toHaveBeenCalledTimes(1);
  expect(await deliveryRows(target.message)).toEqual([{ destination_id: target.secondary, merged_into: null, status: 'sent' }]);
});

it('R2 deleting a claimed primary returns 409, then succeeds without a second send', async () => {
  const control = await deliveryPair('claim-control');
  const send = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await drainDestinationDeliveries(on());
  expect(send).toHaveBeenCalledTimes(1);
  expect((await deliveryRows(control.message)).map(row => row.status)).toEqual(['sent', 'sent']);

  send.mockClear();
  const target = await deliveryPair('claim-delete');
  let signalStarted: (() => void) | undefined;
  let completeSend: (() => void) | undefined;
  const started = new Promise<void>(resolve => { signalStarted = resolve; });
  const completion = new Promise<void>(resolve => { completeSend = resolve; });
  send.mockImplementation(async () => { signalStarted?.(); await completion; return 'receipt'; });
  const draining = drainDestinationDeliveries(on());
  await started;
  try {
    const blocked = await SELF.fetch(`${api}/boss/destinations/${target.primary}`, {
      method: 'DELETE', headers: headers(target.primaryBoss.token),
    });
    expect(blocked.status).toBe(409);
    expect(await blocked.json()).toEqual({ error: 'delivery in progress, retry' });
    expect((await deliveryRows(target.message)).map(row => row.merged_into === null)).toEqual([true, false]);
  } finally {
    completeSend?.();
    await draining;
  }
  const deleted = await SELF.fetch(`${api}/boss/destinations/${target.primary}`, {
    method: 'DELETE', headers: headers(target.primaryBoss.token),
  });
  expect(deleted.status).toBe(200);
  await drainDestinationDeliveries(on());
  expect(send).toHaveBeenCalledTimes(1);
  expect(await deliveryRows(target.message)).toEqual([{ destination_id: target.secondary, merged_into: null, status: 'sent' }]);
});
