// Verifies shared external targets use one persisted send/retry claim.
// Depends on real D1, destination dispatch, and mocked external adapters.
import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, afterEach, expect, it, vi } from 'vitest';
import { seedDatabase } from '../../test-helpers';
import { dispatchDestinations, drainDestinationDeliveries } from '../dispatch';
import * as adapters from '../adapters';
import type { Env, MessageRow } from '../../types';
const on: Env = { ...env, DESTINATIONS_MODE: 'on' };
beforeAll(async () => {
  await seedDatabase();
  for (const id of ['one', 'two']) await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES (?, ?, 'admin')").bind(id, id).run();
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('p', 'telegram', 'Bot', '{}')").run();
});
beforeEach(async () => {
  await env.DB.prepare('DELETE FROM message_deliveries').run();
  await env.DB.prepare('DELETE FROM destination_routes').run();
  await env.DB.prepare('DELETE FROM boss_destinations').run();
  await env.DB.prepare("UPDATE bosses SET preferences = NULL WHERE id IN ('one', 'two')").run();
});
afterEach(() => vi.restoreAllMocks());
async function setup(kind = 'telegram_chat', target = '{"chat_id":"123"}'): Promise<MessageRow> {
  for (const id of ['one', 'two']) await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, provider_id, kind, target, label)
    VALUES (?, ?, 'p', ?, ?, ?)`).bind(id, id, kind, target, id).run();
  const row = await env.DB.prepare("INSERT INTO messages (agent_id, direction, mode, body) VALUES ('test-agent-id', 'agent_to_boss', 'async', 'dedupe') RETURNING *").first<MessageRow>();
  if (!row) throw new Error('fixture failed');
  return row;
}
it('sends once for two bosses sharing a chat, including overlapping dispatch', async () => {
  const message = await setup();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await Promise.all([dispatchDestinations(on, message), dispatchDestinations(on, message)]);
  expect(spy).toHaveBeenCalledTimes(1);
  const rows = await env.DB.prepare('SELECT status, external_message_id, merged_into FROM message_deliveries WHERE message_id = ?').bind(message.id).all();
  expect(rows.results).toHaveLength(2);
  expect(rows.results.every(row => row.status === 'sent' && row.external_message_id === 'receipt')).toBe(true);
  expect(rows.results.filter(row => row.merged_into)).toHaveLength(1);
});
it('keeps distinct Telegram threads distinct', async () => {
  const message = await setup();
  for (const [id, thread] of [['one', '10'], ['two', '20']]) await env.DB.prepare('INSERT INTO destination_routes (destination_id, external_thread_id) VALUES (?, ?)').bind(id, thread).run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await dispatchDestinations(on, message);
  expect(spy).toHaveBeenCalledTimes(2);
});
it('shares one retry claim and mirrors the eventual receipt', async () => {
  const message = await setup();
  const spy = vi.spyOn(adapters, 'sendDestination').mockRejectedValueOnce(new Error('failed')).mockResolvedValue('retry-receipt');
  await dispatchDestinations(on, message);
  await env.DB.prepare("UPDATE message_deliveries SET next_attempt_at = '2000-01-01' WHERE merged_into IS NULL").run();
  await Promise.all([drainDestinationDeliveries(on), drainDestinationDeliveries(on)]);
  expect(spy).toHaveBeenCalledTimes(2);
  const rows = await env.DB.prepare('SELECT status, external_message_id FROM message_deliveries WHERE message_id = ?').bind(message.id).all();
  expect(rows.results.every(row => row.status === 'sent' && row.external_message_id === 'retry-receipt')).toBe(true);
});
it('collapses two destinations for the same device token', async () => {
  const message = await setup('apns', '{"device_id":"device"}');
  await env.DB.prepare("INSERT INTO boss_clients (id, boss_id, kind, label) VALUES ('phone', 'one', 'ios', 'Phone')").run();
  await env.DB.prepare("INSERT INTO boss_devices (id, boss_id, client_id, device_token, bundle_id, environment) VALUES ('device', 'one', 'phone', 'shared-token', 'app', 'sandbox')").run();
  await env.DB.prepare("UPDATE boss_destinations SET boss_id = 'one', provider_id = NULL, client_id = 'phone'").run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue(null);
  await dispatchDestinations(on, message);
  expect(spy).toHaveBeenCalledTimes(1);
});
it('shadow collapses shared chats into a set without sending or creating a mismatch', async () => {
  const message = await setup();
  const spy = vi.spyOn(adapters, 'sendDestination');
  await dispatchDestinations({ ...env, DESTINATIONS_MODE: 'shadow' }, message, [{ channel: 'telegram', config: { chat_id: '123' } }]);
  expect(spy).not.toHaveBeenCalled();
  expect(await env.DB.prepare("SELECT id FROM audit_log WHERE action = 'destination_shadow' AND resource_id = ?").bind(message.id).first()).toBeNull();
  await drainDestinationDeliveries(on);
  expect(spy).not.toHaveBeenCalled();
});
it('uses the immediate boss preference once when a shared chat has mixed quiet hours', async () => {
  const message = await setup();
  const now = new Date();
  await env.DB.prepare("UPDATE bosses SET preferences = ? WHERE id = 'one'").bind(JSON.stringify({ quiet_hours: {
    start: new Date(now.getTime() - 60_000).toISOString().slice(11, 16),
    end: new Date(now.getTime() + 60_000).toISOString().slice(11, 16), timezone: 'UTC', enabled: true,
  } })).run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await dispatchDestinations(on, message);
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1].id).toBe('two');
  expect(await env.DB.prepare('SELECT COUNT(*) AS total FROM message_deliveries WHERE message_id = ? AND next_attempt_at IS NOT NULL').bind(message.id).first()).toEqual({ total: 0 });
});
it('keeps distinct Discord threads separate', async () => {
  const message = await setup('discord_channel', '{"channel_id":"123"}');
  for (const [id, thread] of [['one', '10'], ['two', '20']]) await env.DB.prepare('INSERT INTO destination_routes (destination_id, external_thread_id) VALUES (?, ?)').bind(id, thread).run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await dispatchDestinations(on, { ...message, priority: 'critical' });
  expect(spy).toHaveBeenCalledTimes(2);
});
it('collapses a Discord thread addressed directly or through a route', async () => {
  const message = await setup('discord_channel', '{"channel_id":"10"}');
  await env.DB.prepare("UPDATE boss_destinations SET target = '{\"channel_id\":\"123\"}' WHERE id = 'two'").run();
  await env.DB.prepare("INSERT INTO destination_routes (destination_id, external_thread_id) VALUES ('two', '10')").run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await dispatchDestinations(on, message);
  expect(spy).toHaveBeenCalledTimes(1);
});
it('does not split a webhook target by a channel ID the adapter ignores', async () => {
  const message = await setup('discord_channel', '{"channel_id":"10"}');
  await env.DB.prepare("UPDATE channel_providers SET credentials = '{\"webhook_url\":\"https://discord.com/api/webhooks/1/fake\"}' WHERE id = 'p'").run();
  await env.DB.prepare("UPDATE boss_destinations SET target = '{\"channel_id\":\"20\"}' WHERE id = 'two'").run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await dispatchDestinations(on, message);
  expect(spy).toHaveBeenCalledTimes(1);
});
