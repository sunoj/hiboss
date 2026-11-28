// Verifies shared external targets use one persisted send/retry claim.
// Depends on real D1, destination dispatch, and mocked external adapters.
import { env } from 'cloudflare:test';
import { beforeAll, beforeEach, afterEach, expect, it, vi } from 'vitest';
import { seedDatabase } from '../../test-helpers';
import { liveTokenId } from '../../push/resolution-test-support';
import { dispatchDestinations, drainDestinationDeliveries } from '../dispatch';
import * as adapters from '../adapters';
import type { Env, MessageRow } from '../../types';
const on: Env = { ...env, DESTINATIONS_MODE: 'on' };
beforeAll(async () => {
  await seedDatabase();
  await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES ('one', 'One', 'admin')").run();
});
beforeEach(async () => {
  await env.DB.prepare('DELETE FROM message_deliveries').run();
  await env.DB.prepare('DELETE FROM boss_destinations').run();
  await env.DB.prepare("UPDATE bosses SET preferences = NULL WHERE id = 'one'").run();
});
afterEach(() => vi.restoreAllMocks());
async function setup(): Promise<MessageRow> {
  await env.DB.prepare("INSERT OR IGNORE INTO boss_clients (id, boss_id, kind, label) VALUES ('phone', 'one', 'ios', 'Phone')").run();
  await env.DB.prepare(`INSERT OR IGNORE INTO boss_devices
    (id, boss_id, client_id, device_token, bundle_id, environment, token_id)
    VALUES ('device', 'one', 'phone', 'shared-token', 'app', 'sandbox', ?)`)
    .bind(await liveTokenId('one')).run();
  for (const id of ['one', 'two']) {
    await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, client_id, kind, target, label)
      VALUES (?, 'one', 'phone', 'apns', '{"device_id":"device"}', ?)`).bind(id, id).run();
  }
  const row = await env.DB.prepare("INSERT INTO messages (agent_id, direction, mode, body) VALUES ('test-agent-id', 'agent_to_boss', 'async', 'dedupe') RETURNING *").first<MessageRow>();
  if (!row) throw new Error('fixture failed');
  return row;
}
it('sends once for two destinations sharing a device, including overlapping dispatch', async () => {
  const message = await setup();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await Promise.all([dispatchDestinations(on, message), dispatchDestinations(on, message)]);
  expect(spy).toHaveBeenCalledTimes(1);
  const rows = await env.DB.prepare('SELECT status, external_message_id, merged_into FROM message_deliveries WHERE message_id = ?').bind(message.id).all();
  expect(rows.results).toHaveLength(2);
  expect(rows.results.every(row => row.status === 'sent' && row.external_message_id === 'receipt')).toBe(true);
  expect(rows.results.filter(row => row.merged_into)).toHaveLength(1);
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
  const message = await setup();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue(null);
  await dispatchDestinations(on, message);
  expect(spy).toHaveBeenCalledTimes(1);
});
it('shadow records a shared device without sending', async () => {
  const message = await setup();
  const spy = vi.spyOn(adapters, 'sendDestination');
  await dispatchDestinations({ ...env, DESTINATIONS_MODE: 'shadow' }, message);
  expect(spy).not.toHaveBeenCalled();
  const rows = await env.DB.prepare('SELECT status, next_attempt_at FROM message_deliveries WHERE message_id = ?')
    .bind(message.id).all();
  expect(rows.results).toEqual(Array(2).fill({ status: 'queued', next_attempt_at: null }));
  await drainDestinationDeliveries(on);
  expect(spy).not.toHaveBeenCalled();
});
it('uses the immediate boss preference once when shared device destinations have mixed quiet hours', async () => {
  const message = await setup();
  const now = new Date();
  await env.DB.prepare("UPDATE bosses SET preferences = ? WHERE id = 'one'").bind(JSON.stringify({ quiet_hours: {
    start: new Date(now.getTime() - 60_000).toISOString().slice(11, 16),
    end: new Date(now.getTime() + 60_000).toISOString().slice(11, 16), timezone: 'UTC', enabled: true,
  } })).run();
  await env.DB.prepare("UPDATE boss_destinations SET honours_quiet_hours = 0 WHERE id = 'two'").run();
  const spy = vi.spyOn(adapters, 'sendDestination').mockResolvedValue('receipt');
  await dispatchDestinations(on, message);
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1].id).toBe('two');
  expect(await env.DB.prepare('SELECT COUNT(*) AS total FROM message_deliveries WHERE message_id = ? AND next_attempt_at IS NOT NULL').bind(message.id).first()).toEqual({ total: 0 });
});
