// Archive selection integration coverage for routing, authentication, and publication.
// Uses real D1/Worker routes plus a stub callback transport; no external services.
import { env, SELF } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, expect, it, vi } from 'vitest';
import { authHeaders, seedBossToken, seedDatabase } from '../test-helpers';
import { hashApiKey } from '../middleware/auth';
import { bossCanAccessAgent, panelTargetAccessSql, resolvedBosses } from '../panels/access';
import { notifyBossAgents } from '../notify';
import { resolveDestinations } from '../delivery/destinations';
import { findInboundRoute } from '../delivery/inbound';
import { resolveBossForChannel } from './webhook-helpers';
import { ensureThreadForSession } from './message-option-threads';
import { getAgentQuietHoursEnd } from './quiet-hours';
import type { MessageRow } from '../types';

let manager: string;
let admin: string;
let message: MessageRow;
const archive = (): Promise<D1Result> => env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?").bind(manager).run();

beforeAll(async () => {
  await seedDatabase();
  admin = await seedBossToken('Admin A', 'admin', 'selection-admin');
  manager = await seedBossToken('Manager M', 'manager', 'selection-manager');
  await env.DB.prepare('INSERT INTO boss_agent_access VALUES (?, ?)').bind(manager, 'test-agent-id').run();
  await env.DB.prepare("INSERT INTO api_keys (id, name, key_hash, callback_url) VALUES ('callback-agent', 'Callback', 'callback-hash', 'https://callback.test')").run();
  await env.DB.prepare(`UPDATE bosses SET agent_id = 'callback-agent', telegram_user_id = '1234',
    preferences = '{"quiet_hours":{"start":"00:00","end":"23:59","timezone":"UTC"}}' WHERE id = ?`).bind(manager).run();
  await env.DB.prepare("INSERT INTO sessions (id, agent_id) VALUES ('archive-session', 'test-agent-id')").run();
  const row = await env.DB.prepare("INSERT INTO messages (agent_id, direction, mode, body) VALUES ('test-agent-id', 'agent_to_boss', 'async', 'Archive test') RETURNING *").first<MessageRow>();
  if (!row) throw new Error('message seed failed');
  message = row;
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('archive-provider', 'telegram', 'Archive', '{}')").run();
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, provider_id, label, target)
    VALUES ('archive-destination', ?, 'telegram_chat', 'archive-provider', 'Archive', '{"chat_id":"1234"}')`).bind(manager).run();
  await env.DB.prepare("INSERT INTO inbound_routes (id, destination_id, target_agent_id) VALUES ('archive-inbound', 'archive-destination', 'test-agent-id')").run();
});
beforeEach(async () => { await env.DB.prepare('UPDATE bosses SET archived_at = NULL WHERE id = ?').bind(manager).run(); });
afterEach(() => vi.unstubAllGlobals());

it('excludes a granted archived manager from agent discovery, access, and default publication', async () => {
  expect((await resolvedBosses(env.DB, 'test-agent-id')).map(boss => boss.id)).toContain(manager);
  await archive();
  const bosses = await SELF.fetch('https://test.local/api/agents/me/bosses', { headers: authHeaders() });
  expect(await bosses.json()).toEqual({ bosses: [{ id: admin, name: 'Admin A', role: 'admin' }], defaultBossId: admin });
  expect(await bossCanAccessAgent(env.DB, manager, 'test-agent-id')).toBe(false);
  const published = await publish('archive-default');
  expect(published.status).toBe(201);
  const receipt = await published.json() as { panelId: string };
  const panel = await SELF.fetch(`https://test.local/api/panels/${receipt.panelId}`, { headers: authHeaders() });
  expect(await panel.json()).toMatchObject({ targetBossId: admin });
  expect((await publish('archive-explicit', manager)).status).toBe(404);
});

it('retains panels and messages while removing their archived target from mutation access', async () => {
  const published = await publish('archive-history', manager);
  expect(published.status).toBe(201);
  const { panelId } = await published.json() as { panelId: string };
  await archive();
  const detail = await SELF.fetch(`https://test.local/api/panels/${panelId}`, { headers: authHeaders() });
  expect(detail.status).toBe(200);
  expect(await detail.json()).toMatchObject({ targetBossId: manager });
  for (const table of ['p', 'panels'] as const) {
    const match = await env.DB.prepare(`SELECT 1 FROM panels ${table} WHERE ${table}.panel_id = ? AND ${panelTargetAccessSql(table)}`).bind(panelId).first();
    expect(match).toBeNull();
  }
  expect(await env.DB.prepare('SELECT id FROM messages WHERE id = ?').bind(message.id).first()).toEqual({ id: message.id });
});

it('excludes archived managers and admins from callback fan-out', async () => {
  const transport = vi.fn().mockResolvedValue(new Response('{}'));
  vi.stubGlobal('fetch', transport);
  await notifyBossAgents(env, 'test-agent-id', message);
  expect(transport).toHaveBeenCalledTimes(1);
  transport.mockClear();
  await archive();
  await notifyBossAgents(env, 'test-agent-id', message);
  expect(transport).not.toHaveBeenCalled();
  await env.DB.prepare("UPDATE bosses SET role = 'admin' WHERE id = ?").bind(manager).run();
  await notifyBossAgents(env, 'test-agent-id', message);
  expect(transport).not.toHaveBeenCalled();
  expect(await bossCanAccessAgent(env.DB, manager, 'test-agent-id')).toBe(false);
  await env.DB.prepare("UPDATE bosses SET role = 'manager' WHERE id = ?").bind(manager).run();
});

it('excludes archived destinations, inbound identities, and quiet hours', async () => {
  expect(await resolveDestinations(env, message)).toHaveLength(1);
  expect(await findInboundRoute(env, 'telegram', '1234')).not.toBeNull();
  expect((await resolveBossForChannel(env, 'telegram', '1234', false)).boss?.id).toBe(manager);
  expect(await getAgentQuietHoursEnd(env, 'test-agent-id', new Date('2026-09-13T12:00:00Z'))).not.toBeNull();
  await archive();
  expect(await resolveDestinations(env, message)).toEqual([]);
  expect(await findInboundRoute(env, 'telegram', '1234')).toBeNull();
  expect(await resolveBossForChannel(env, 'telegram', '1234', false)).toEqual({ boss: null, error: 'unknown sender' });
  expect(await getAgentQuietHoursEnd(env, 'test-agent-id', new Date('2026-09-13T12:00:00Z'))).toBeNull();
});

it('keeps anonymous webhook access closed when every boss is archived', async () => {
  await archive();
  await env.DB.prepare("UPDATE bosses SET archived_at = datetime('now') WHERE id = ?").bind(admin).run();
  try {
    expect(await resolveBossForChannel(env, 'telegram', '1234', false)).toEqual({ boss: null, error: 'unknown sender' });
    expect(await resolvedBosses(env.DB, 'test-agent-id')).toEqual([]);
  } finally {
    await env.DB.prepare('UPDATE bosses SET archived_at = NULL WHERE id = ?').bind(admin).run();
  }
});

it('invites only live granted bosses to Discord threads', async () => {
  await env.DB.prepare("UPDATE bosses SET discord_user_id = '5678' WHERE id = ?").bind(manager).run();
  const transport = vi.fn(async (url: string) => url.endsWith('/threads')
    ? Response.json({ id: 'archive-thread' }) : new Response(null, { status: 204 }));
  vi.stubGlobal('fetch', transport);
  const invites = (): number => transport.mock.calls.filter(([url]) => url.includes('/thread-members/')).length;
  const discord = { channel: 'discord' as const, config: { use_threads: true, bot_token: 'test-bot', channel_id: '100' } };
  const openThread = async (sessionId: string): Promise<string | undefined> => {
    await env.DB.prepare("INSERT INTO sessions (id, agent_id) VALUES (?, 'test-agent-id')").bind(sessionId).run();
    return ensureThreadForSession(env, 'test-agent-id', sessionId, discord, 'discord-message');
  };
  expect(await openThread('thread-live')).toBe('archive-thread');
  expect(invites()).toBe(1);
  transport.mockClear();
  await archive();
  expect(await openThread('thread-archived')).toBe('archive-thread');
  expect(invites()).toBe(0);
});

it('does not consume a pairing code or issue a token for an archived boss', async () => {
  const code = `hb_pair_${'a'.repeat(64)}`;
  await env.DB.prepare("INSERT INTO boss_pairing_codes (id, boss_id, code_hash, expires_at) VALUES ('archive-pair', ?, ?, '2999-01-01T00:00:00Z')")
    .bind(manager, await hashApiKey(code)).run();
  await archive();
  const response = await SELF.fetch('https://test.local/api/pairing/redeem', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code, device_label: 'Archive test' }) });
  expect(response.status).toBe(400);
  expect(await env.DB.prepare("SELECT consumed_at, redeemed_token_id FROM boss_pairing_codes WHERE id = 'archive-pair'").first()).toEqual({ consumed_at: null, redeemed_token_id: null });
});

function publish(key: string, targetBossId?: string): Promise<Response> {
  return SELF.fetch('https://test.local/api/panels', { method: 'POST', headers: { ...authHeaders(), 'Idempotency-Key': key }, body: JSON.stringify({
    protocolVersion: 2, targetBossId, sessionId: 'archive-session', taskKey: key, title: 'Archive test', catalogId: 'hiboss.panel', catalogVersion: 1,
    spec: { root: 'text', elements: { text: { type: 'Text', props: { text: 'History stays' }, children: [] } } },
    stateSchema: { type: 'object', required: ['task'], additionalProperties: false, properties: { task: { type: 'object', required: ['count'], additionalProperties: false, properties: { count: { type: 'integer' } } } } },
    initialState: { task: { count: 0 } },
  }) });
}
