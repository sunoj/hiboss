// Reproduces six business lifecycle audit hypotheses with a legitimate control for each.
// Covers join decisions, Discord reactions, reused sessions, and queued deliveries.
// Depends on the Worker API, seeded D1 tables, and delivery helpers.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, expect, it, vi } from 'vitest';
import { createAgent } from '../agent-keys';
import { persistDiscordReaction } from '../discord-gateway-reactions';
import { resolveDestinations } from '../delivery/destinations';
import { handleScheduled } from '../scheduled';
import { seedBossToken, seedDatabase } from '../test-helpers';
import type { Env } from '../types';

const api = 'https://test.local/api';
const unique = (name: string): string => `lifecycle-${name}-${crypto.randomUUID()}`;
const headers = (token: string): Record<string, string> => ({ Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' });

beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS join_requests (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, poll_token TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    api_key_id TEXT REFERENCES api_keys(id), api_key TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')))` ).run();
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
  await env.DB.prepare("INSERT INTO join_requests (id, name, poll_token) VALUES (?, ?, ?)")
    .bind(controlId, unique('rejected-agent'), unique('poll')).run();
  const control = await SELF.fetch(`${api}/boss/join-requests/${controlId}/reject`, { method: 'POST', headers: headers(admin.token) });
  expect(control.status).toBe(200);
  expect(await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?').bind(controlId).first()).toEqual({ status: 'rejected' });

  for (let index = 0; index < 8; index++) {
    const id = unique(`join-race-${index}`);
    const name = unique(`race-agent-${index}`);
    await env.DB.prepare('INSERT INTO join_requests (id, name, poll_token) VALUES (?, ?, ?)')
      .bind(id, name, unique('poll')).run();
    expect(await env.DB.prepare('SELECT status FROM join_requests WHERE id = ?').bind(id).first()).toEqual({ status: 'pending' });
    const [approval, rejection] = await Promise.all(['approve', 'reject'].map(action =>
      SELF.fetch(`${api}/boss/join-requests/${id}/${action}`, { method: 'POST', headers: headers(admin.token) })));
    const row = await env.DB.prepare('SELECT status, api_key_id FROM join_requests WHERE id = ?').bind(id)
      .first<{ status: string; api_key_id: string | null }>();
    const created = await env.DB.prepare('SELECT id FROM api_keys WHERE name = ?').bind(name).first<{ id: string }>();
    expect([approval.status, rejection.status].filter(status => status === 200)).toHaveLength(1);
    expect(row?.status === 'approved' ? row.api_key_id === created?.id : created === null).toBe(true);
  }
});

it('F12 unbound Discord user cannot change a stored reaction', async () => {
  const owner = await boss('reaction-owner', 'manager');
  const source = await agent('reaction-agent');
  const channel = unique('discord-channel');
  const message = unique('reaction-message');
  const discordId = unique('discord-message');
  const ownerUser = unique('owner-user');
  await env.DB.prepare('UPDATE bosses SET discord_user_id = ? WHERE id = ?').bind(ownerUser, owner.id).run();
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(owner.id, source.id).run();
  await env.DB.prepare("INSERT INTO channel_configs (agent_id, channel, config) VALUES (?, 'discord', ?)")
    .bind(source.id, JSON.stringify({ channel_id: channel, bot_token: 'fixture' })).run();
  await env.DB.prepare(`INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, metadata)
    VALUES (?, ?, 'agent_to_boss', 'async', 'discord', 'question', 'delivered', ?)`)
    .bind(message, source.id, JSON.stringify({ discord_message_id: discordId })).run();
  const reaction = (user_id: string) => ({ user_id, channel_id: channel, message_id: discordId, emoji: { id: null, name: '✅' } });
  expect(await persistDiscordReaction(env, source.id, reaction(ownerUser), 'add')).toBe(true);
  const read = async () => {
    const row = await env.DB.prepare('SELECT metadata FROM messages WHERE id = ?').bind(message).first<{ metadata: string }>();
    return (JSON.parse(row!.metadata) as { reactions: { emoji: string; user: string }[] }).reactions;
  };
  expect(await read()).toEqual([{ emoji: '✅', user: ownerUser }]);
  expect(await persistDiscordReaction(env, source.id, reaction(unique('unbound-user')), 'add')).toBe(false);
  expect(await read()).toEqual([{ emoji: '✅', user: ownerUser }]);
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

it('F23 deleted session route does not apply when another agent reuses its id', async () => {
  const previous = await agent('route-previous');
  const next = await agent('route-next');
  const admin = await boss('route-admin');
  const session = unique('route-session');
  const destination = unique('destination');
  const provider = unique('provider');
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES (?, 'discord', ?, ?)")
    .bind(provider, provider, JSON.stringify({ bot_token: 'fixture' })).run();
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label)
    VALUES (?, ?, 'discord_channel', ?, ?, 'route control')`)
    .bind(destination, admin.id, provider, JSON.stringify({ channel_id: 'default-channel' })).run();
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(session, previous.id).run();
  await env.DB.prepare('INSERT INTO destination_routes (destination_id, session_id, external_channel_id) VALUES (?, ?, ?)')
    .bind(destination, session, 'previous-channel').run();
  const message = (agent_id: string) => ({ agent_id, session_id: session, priority: 'normal' as const, direction: 'agent_to_boss' as const });
  expect((await resolveDestinations(env, message(previous.id)))[0]?.config['channel_id']).toBe('previous-channel');
  const deleted = await SELF.fetch(`${api}/sessions/${session}`, { method: 'DELETE', headers: headers(previous.key) });
  expect(deleted.status).toBe(200);
  await env.DB.prepare('INSERT INTO sessions (id, agent_id) VALUES (?, ?)').bind(session, next.id).run();
  expect((await resolveDestinations(env, message(next.id)))[0]?.config['channel_id']).toBe('default-channel');
});

it('F24 disabled channel cannot send a previously queued legacy delivery', async () => {
  const source = await agent('queue-agent');
  const manager = await boss('queue-manager', 'manager');
  const channel = unique('queue-channel');
  const originalMode = env.DESTINATIONS_MODE;
  env.DESTINATIONS_MODE = 'off';
  try {
    await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(manager.id, source.id).run();
    await env.DB.prepare("INSERT INTO channel_configs (id, agent_id, channel, config) VALUES (?, ?, 'telegram', ?)")
      .bind(channel, source.id, JSON.stringify({ bot_token: 'fixture', chat_id: 'fixture-chat' })).run();
    const enqueue = async () => {
      const message = unique('queued-message');
      const delivery = unique('delivery');
      await insertMessage(message, source.id);
      await env.DB.prepare(`INSERT INTO delivery_queue (id, message_id, agent_id, channel, config, scheduled_at)
        VALUES (?, ?, ?, 'telegram', ?, '2020-01-01T00:00:00Z')`)
        .bind(delivery, message, source.id, JSON.stringify({ bot_token: 'fixture', chat_id: 'fixture-chat' })).run();
      return delivery;
    };
    const fetchMock = vi.fn(async () => Response.json({ ok: true, result: { message_id: 1 } }));
    vi.stubGlobal('fetch', fetchMock);
    const control = await enqueue();
    await handleScheduled(env as Env);
    expect(await env.DB.prepare('SELECT status FROM delivery_queue WHERE id = ?').bind(control).first()).toEqual({ status: 'delivered' });
    expect(fetchMock).toHaveBeenCalled();
    const pending = await enqueue();
    fetchMock.mockClear();
    const disabled = await SELF.fetch(`${api}/boss/channels/${channel}`, {
      method: 'PATCH', headers: headers(manager.token), body: JSON.stringify({ enabled: false }),
    });
    expect(disabled.status).toBe(200);
    expect(await env.DB.prepare('SELECT enabled FROM channel_configs WHERE id = ?').bind(channel).first()).toEqual({ enabled: 0 });
    await handleScheduled(env as Env);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(await env.DB.prepare('SELECT status FROM delivery_queue WHERE id = ?').bind(pending).first())
      .not.toEqual({ status: 'delivered' });
  } finally { env.DESTINATIONS_MODE = originalMode; }
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
