// Checks join, session reuse, and destination deletion invariants.
// Depends on the Worker API, seeded D1 tables, and delivery helpers.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import { createAgent } from '../agent-keys';
import { insertPendingJoin, seedBossToken, seedDatabase } from '../test-helpers';

const api = 'https://test.local/api';
const unique = (name: string): string => `lifecycle-${name}-${crypto.randomUUID()}`;
const headers = (token: string): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });

beforeAll(async () => {
  await seedDatabase();
});
afterEach(() => { vi.unstubAllGlobals(); });

async function agent(name: string) {
  const created = await createAgent(env.DB, unique(name), { type: 'system', id: 'lifecycle-test' });
  if (!created) throw new Error('agent fixture failed');
  return created;
}

async function boss(name: string, role = 'admin') {
  const id = unique(name);
  const token = `hb_${id}`;
  await seedBossToken(id, role, token, id);
  return { id, token };
}

async function insertMessage(id: string, agentId: string): Promise<void> {
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status)
    VALUES (?, ?, 'agent_to_boss', 'async', 'telegram', 'lifecycle payload', 'sent')`).bind(id, agentId).run();
}

it('F10 concurrent approve and reject yield exactly one terminal decision', async () => {
  const admin = await boss('join-admin');
  const controlId = unique('join-control');
  await insertPendingJoin(controlId, unique('rejected-agent'));
  const control = await SELF.fetch(`${api}/boss/join-requests/${controlId}/reject`, { method: 'POST', headers: headers(admin.token) });
  expect(control.status).toBe(200);
  expect(await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?').bind(controlId).first()).toEqual({ status: 'rejected' });

  for (let index = 0; index < 8; index++) {
    const id = unique(`join-race-${index}`);
    const name = unique(`race-agent-${index}`);
    await insertPendingJoin(id, name);
    expect(await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?').bind(id).first()).toEqual({ status: 'pending' });
    const [approval, rejection] = await Promise.all(['approve', 'reject'].map(action =>
      SELF.fetch(`${api}/boss/join-requests/${id}/${action}`, { method: 'POST', headers: headers(admin.token) })));
    const row = await env.DB.prepare('SELECT status, device_id FROM join_requests WHERE id = ?').bind(id)
      .first<{ status: string; device_id: string | null }>();
    const created = await env.DB.prepare('SELECT device_id FROM api_keys WHERE name = ?').bind(name).first<{ device_id: string }>();
    expect([approval.status, rejection.status].filter(status => status === 200)).toHaveLength(1);
    expect(row?.status === 'approved' ? row.device_id === created?.device_id : created === null).toBe(true);
  }
});

it('F22 reused session id does not expose the previous agent session events', async () => {
  const previous = await agent('previous-session-owner');
  const next = await agent('next-session-owner');
  const session = unique('reused-session');
  const event = unique('old-event');
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(session, previous.id).run();
  await env.DB.prepare("INSERT INTO session_events (id, session_id, sequence, kind, raw) VALUES (?, ?, 1, 'message', ?)")
    .bind(event, session, JSON.stringify({ body: 'previous owner private event' })).run();
  const path = `${api}/sessions/${session}/events`;
  const prior = await SELF.fetch(path, { headers: headers(previous.key) });
  expect(prior.status).toBe(200);
  expect((await prior.json() as { events: { id: string }[] }).events).toMatchObject([{ id: event }]);
  const deleted = await SELF.fetch(`${api}/sessions/${session}`, { method: 'DELETE', headers: headers(previous.key) });
  expect(deleted.status).toBe(200);
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(session, next.id).run();
  const reused = await SELF.fetch(path, { headers: headers(next.key) });
  expect(reused.status).toBe(200);
  expect((await reused.json() as { events: unknown[] }).events).toEqual([]);
});

it('F25 deleting a primary destination retains another boss merged delivery', async () => {
  const primaryBoss = await boss('primary-boss');
  const otherBoss = await boss('other-boss');
  const source = await agent('merged-agent');
  const message = unique('merged-message');
  const primary = unique('primary-destination');
  const secondary = unique('secondary-destination');
  const first = unique('primary-delivery');
  const second = unique('secondary-delivery');
  await insertMessage(message, source.id);
  for (const [id, bossId] of [[primary, primaryBoss.id], [secondary, otherBoss.id]]) {
    await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, target, label)
      VALUES (?, ?, 'native_live', '{}', 'merged fixture')`).bind(id, bossId).run();
  }
  await env.DB.prepare('INSERT INTO message_deliveries (id, message_id, destination_id, status) VALUES (?, ?, ?, ?)')
    .bind(first, message, primary, 'queued').run();
  await env.DB.prepare('INSERT INTO message_deliveries (id, message_id, destination_id, status, merged_into) VALUES (?, ?, ?, ?, ?)')
    .bind(second, message, secondary, 'queued', first).run();
  const visible = await SELF.fetch(`${api}/boss/destinations`, { headers: headers(otherBoss.token) });
  expect(visible.status).toBe(200);
  expect((await visible.json() as { destinations: { id: string }[] }).destinations.map(row => row.id)).toContain(secondary);
  expect(await env.DB.prepare('SELECT merged_into FROM message_deliveries WHERE id = ?').bind(second).first())
    .toEqual({ merged_into: first });
  const deleted = await SELF.fetch(`${api}/boss/destinations/${primary}`, { method: 'DELETE', headers: headers(primaryBoss.token) });
  expect(deleted.status).toBe(200);
  expect(await env.DB.prepare('SELECT id, destination_id FROM message_deliveries WHERE id = ?').bind(second).first())
    .toEqual({ id: second, destination_id: secondary });
});
