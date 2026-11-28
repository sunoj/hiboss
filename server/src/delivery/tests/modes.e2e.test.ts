// Exercises destination fan-out through the authenticated message API and cron.
// Depends on real Worker/D1 storage and mocked external delivery adapters.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, afterEach, expect, it, vi } from 'vitest';
import app from '../../index';
import { authHeaders, seedDatabase, seedBossToken } from '../../test-helpers';
import * as adapter from '../adapters';
import { liveTokenId } from '../../push/resolution-test-support';
import { handleScheduled } from '../../scheduled';
import type { Env } from '../../types';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Destinations', 'admin', 'destination-admin', 'destination-boss');
  await env.DB.prepare(`INSERT INTO boss_devices (id, boss_id, device_token, bundle_id, environment, token_id)
    VALUES ('mode-device', 'destination-boss', 'mode-token', 'app', 'sandbox', ?)`)
    .bind(await liveTokenId('destination-boss')).run();
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, target, label)
    VALUES ('destination', 'destination-boss', 'apns', '{"device_id":"mode-device"}', 'Push')`).run();
});
afterEach(() => vi.restoreAllMocks());

async function send(mode?: string): Promise<string> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request('https://test/api/messages', {
    method: 'POST', headers: authHeaders(),
    body: JSON.stringify({ body: 'hello', channel: 'discord', options: ['A', 'B'],
      metadata: { option_descriptions: [{ label: 'B', text: 'Keep current' }] } }),
  }), { ...env, DESTINATIONS_MODE: mode, PUSH_RELAY_URL: 'off' } as Env, ctx);
  await waitOnExecutionContext(ctx);
  expect(response.status).toBe(201);
  return (await response.json() as { id: string }).id;
}

it('stores app-only messages in off mode without destination delivery rows', async () => {
  const spy = vi.spyOn(adapter, 'sendDestination').mockResolvedValue(null);
  const id = await send();
  expect(await env.DB.prepare('SELECT channel FROM messages WHERE id = ?').bind(id).first())
    .toEqual({ channel: null });
  expect(spy).not.toHaveBeenCalled();
  expect(await env.DB.prepare('SELECT id FROM message_deliveries WHERE message_id = ?').bind(id).first()).toBeNull();
});

it('shadow records queued destinations without sending them', async () => {
  const spy = vi.spyOn(adapter, 'sendDestination').mockResolvedValue(null);
  const id = await send('shadow');
  expect(spy).not.toHaveBeenCalled();
  expect(await env.DB.prepare('SELECT status, next_attempt_at FROM message_deliveries WHERE message_id = ?').bind(id).first())
    .toEqual({ status: 'queued', next_attempt_at: null });
  await handleScheduled({ ...env, DESTINATIONS_MODE: 'on' } as Env);
  expect(spy).not.toHaveBeenCalled();
});

it('on ignores channel hints, schedules failure, and retries through cron', async () => {
  const spy = vi.spyOn(adapter, 'sendDestination').mockRejectedValueOnce(new Error('temporary failure'))
    .mockResolvedValue(null);
  const id = await send('on');
  expect(spy).toHaveBeenCalledTimes(1);
  expect(await env.DB.prepare('SELECT status, attempts FROM message_deliveries WHERE message_id = ?').bind(id).first())
    .toEqual({ status: 'failed', attempts: 1 });
  await env.DB.prepare("UPDATE message_deliveries SET next_attempt_at = '2000-01-01' WHERE message_id = ?").bind(id).run();
  await handleScheduled({ ...env, DESTINATIONS_MODE: 'on' } as Env);
  expect(spy).toHaveBeenCalledTimes(2);
  expect(await env.DB.prepare('SELECT status, attempts, external_message_id, next_attempt_at FROM message_deliveries WHERE message_id = ?').bind(id).first())
    .toEqual({ status: 'sent', attempts: 2, external_message_id: null, next_attempt_at: null });
});
