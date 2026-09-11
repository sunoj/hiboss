// Destination delivery integration tests for APNs, route overrides, and retry safety.
// Depends on real D1 and injected adapter failures; external networks are mocked.
import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, afterEach, expect, it, vi } from 'vitest';
import { seedDatabase } from '../../test-helpers';
import { dispatchDestinations, drainDestinationDeliveries } from '../dispatch';
import { resolveDestinations } from '../destinations';
import * as adapters from '../adapters';
import * as push from '../../apns';
import type { MessageRow, Env } from '../../types';

const on: Env = { ...env, DESTINATIONS_MODE: 'on' };
beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES ('retry-boss', 'Boss', 'admin')").run();
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('retry-provider', 'discord', 'Bot', '{\"bot_token\":\"token\"}')").run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label) VALUES ('retry-dest', 'retry-boss', 'discord_channel', 'retry-provider', '{\"channel_id\":\"10\"}', 'Chat')").run();
});
beforeEach(async () => {
  await env.DB.prepare("DELETE FROM message_deliveries WHERE destination_id IN (SELECT id FROM boss_destinations WHERE boss_id = 'retry-boss')").run();
  await env.DB.prepare("DELETE FROM boss_destinations WHERE boss_id = 'retry-boss' AND id != 'retry-dest'").run();
  await env.DB.prepare("UPDATE boss_destinations SET enabled = 1 WHERE id = 'retry-dest'").run();
  await env.DB.prepare("UPDATE bosses SET preferences = NULL WHERE id = 'retry-boss'").run();
});
afterEach(() => vi.restoreAllMocks());
async function message(): Promise<MessageRow> {
  const row = await env.DB.prepare("INSERT INTO messages (agent_id, direction, mode, body) VALUES ('test-agent-id', 'agent_to_boss', 'async', 'retry') RETURNING *").first<MessageRow>();
  if (!row) throw new Error('fixture insert failed');
  return row;
}
async function due(id: string): Promise<void> {
  await env.DB.prepare("UPDATE message_deliveries SET next_attempt_at = '2000-01-01' WHERE message_id = ? AND status = 'failed'").bind(id).run();
}

it('claims due rows once across overlapping cron executions and caps retries', async () => {
  const spy = vi.spyOn(adapters, 'sendDestination').mockRejectedValue(new Error('https://secret-token'));
  const row = await message();
  await dispatchDestinations(on, row);
  await due(row.id);
  await Promise.all([drainDestinationDeliveries(on), drainDestinationDeliveries(on)]);
  expect(spy).toHaveBeenCalledTimes(2);
  await due(row.id);
  await drainDestinationDeliveries(on);
  expect(spy).toHaveBeenCalledTimes(3);
  const result = await env.DB.prepare('SELECT status, attempts, next_attempt_at, last_error FROM message_deliveries WHERE message_id = ?').bind(row.id).first();
  expect(result).toEqual({ status: 'failed', attempts: 3, next_attempt_at: null, last_error: 'destination send failed' });
  await drainDestinationDeliveries(on);
  expect(spy).toHaveBeenCalledTimes(3);
});
it('rechecks enabled state before retrying', async () => {
  const spy = vi.spyOn(adapters, 'sendDestination').mockRejectedValue(new Error('failed'));
  const row = await message();
  await dispatchDestinations(on, row);
  await env.DB.prepare("UPDATE boss_destinations SET enabled = 0 WHERE id = 'retry-dest'").run();
  await due(row.id);
  await drainDestinationDeliveries(on);
  expect(spy).toHaveBeenCalledTimes(1);
  expect(await env.DB.prepare('SELECT next_attempt_at FROM message_deliveries WHERE message_id = ?').bind(row.id).first()).toEqual({ next_attempt_at: null });
});
it('defers per-destination quiet hours and allows an opt-out destination immediately', async () => {
  const now = new Date();
  const start = new Date(now.getTime() - 60_000).toISOString().slice(11, 16);
  const end = new Date(now.getTime() + 60_000).toISOString().slice(11, 16);
  await env.DB.prepare("UPDATE bosses SET preferences = ? WHERE id = 'retry-boss'")
    .bind(JSON.stringify({ quiet_hours: { enabled: true, start, end, timezone: 'UTC' } })).run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label, honours_quiet_hours) VALUES ('immediate', 'retry-boss', 'discord_channel', 'retry-provider', '{\"channel_id\":\"11\"}', 'Immediate', 0)").run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('external-id');
  const row = await message();
  await dispatchDestinations(on, { ...row, priority: 'high' });
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1].id).toBe('immediate');
  expect(await env.DB.prepare("SELECT status, attempts FROM message_deliveries WHERE message_id = ? AND destination_id = 'retry-dest'").bind(row.id).first())
    .toEqual({ status: 'queued', attempts: 0 });
  await env.DB.prepare("UPDATE bosses SET preferences = NULL WHERE id = 'retry-boss'").run();
  await env.DB.prepare("UPDATE message_deliveries SET next_attempt_at = '2000-01-01' WHERE message_id = ? AND destination_id = 'retry-dest'").bind(row.id).run();
  await drainDestinationDeliveries(on);
  expect(spy).toHaveBeenCalledTimes(2);
});
it('resolves Discord thread overrides independently of legacy session columns', async () => {
  await env.DB.prepare("INSERT INTO sessions (id, agent_id, discord_thread_id) VALUES ('retry-session', 'test-agent-id', 'old-thread')").run();
  await env.DB.prepare("INSERT INTO destination_routes (destination_id, session_id, external_channel_id, external_thread_id) VALUES ('retry-dest', 'retry-session', '20', '30')").run();
  const row = await message();
  const result = await resolveDestinations(on, { ...row, session_id: 'retry-session' });
  expect(result[0].config).toMatchObject({ channel_id: '30', thread_id: '30' });
});
it('sends APNs only to the resolved live device and keeps native eligibility queued', async () => {
  await env.DB.prepare("UPDATE boss_destinations SET enabled = 0 WHERE id = 'retry-dest'").run();
  await env.DB.prepare("INSERT INTO boss_clients (id, boss_id, kind, label) VALUES ('phone', 'retry-boss', 'ios', 'Phone')").run();
  await env.DB.prepare("INSERT INTO boss_devices (id, boss_id, client_id, device_token, bundle_id, environment) VALUES ('device', 'retry-boss', 'phone', 'push-token', 'app', 'sandbox')").run();
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, client_id, target, label) VALUES
    ('push', 'retry-boss', 'apns', 'phone', '{"device_id":"device"}', 'Push'),
    ('native', 'retry-boss', 'native_live', 'phone', '{}', 'Native')`).run();
  const spy = vi.spyOn(push, 'sendPush').mockResolvedValue({ ok: true, prune: false });
  const row = await message();
  await dispatchDestinations(on, { ...row, priority: 'low' });
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1]).toBe('push-token');
  expect(await env.DB.prepare("SELECT status, attempts FROM message_deliveries WHERE message_id = ? AND destination_id = 'native'").bind(row.id).first())
    .toEqual({ status: 'queued', attempts: 0 });
  await env.DB.prepare("UPDATE boss_clients SET revoked_at = datetime('now') WHERE id = 'phone'").run();
  expect(await resolveDestinations(on, row)).toEqual([]);
});
