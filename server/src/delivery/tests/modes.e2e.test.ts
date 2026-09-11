// Exercises destination fan-out through the authenticated message API and cron.
// Depends on real Worker/D1 storage and mocked external delivery adapters.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, afterEach, expect, it, vi } from 'vitest';
import app from '../../index';
import { authHeaders, seedDatabase, seedBossToken } from '../../test-helpers';
import * as adapter from '../../routes/delivery';
import { handleScheduled } from '../../scheduled';
import type { Env } from '../../types';

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Destinations', 'admin', 'destination-admin', 'destination-boss');
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('provider', 'telegram', 'Bot', ?)")
    .bind(JSON.stringify({ bot_token: 'test-token' })).run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label) VALUES ('destination', 'destination-boss', 'telegram_chat', 'provider', ?, 'Chat')")
    .bind(JSON.stringify({ chat_id: 'new-chat' })).run();
  await env.DB.prepare("INSERT INTO channel_configs (agent_id, channel, config) VALUES ('test-agent-id', 'telegram', ?)")
    .bind(JSON.stringify({ bot_token: 'legacy-token', chat_id: 'old-chat' })).run();
});
afterEach(() => vi.restoreAllMocks());

async function send(mode?: string): Promise<string> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request('https://test/api/messages', {
    method: 'POST', headers: authHeaders(), body: JSON.stringify({ body: 'hello', channel: 'discord' }),
  }), { ...env, DESTINATIONS_MODE: mode } as Env, ctx);
  await waitOnExecutionContext(ctx);
  expect(response.status).toBe(201);
  return (await response.json() as { id: string }).id;
}

it('defaults to off with only the legacy adapter and no delivery rows', async () => {
  const spy = vi.spyOn(adapter, 'deliverToChannelWithOptions').mockResolvedValue({ delivered: true });
  const id = await send();
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1].chat_id).toBe('old-chat');
  expect(await env.DB.prepare('SELECT id FROM message_deliveries WHERE message_id = ?').bind(id).first()).toBeNull();
});

it('shadow records queued deliveries and disagreement while only legacy sends', async () => {
  const spy = vi.spyOn(adapter, 'deliverToChannelWithOptions').mockResolvedValue({ delivered: true });
  const id = await send('shadow');
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1].chat_id).toBe('old-chat');
  expect(await env.DB.prepare('SELECT status, next_attempt_at FROM message_deliveries WHERE message_id = ?').bind(id).first())
    .toEqual({ status: 'queued', next_attempt_at: null });
  expect(await env.DB.prepare("SELECT id FROM audit_log WHERE action = 'destination_shadow' AND resource_id = ?").bind(id).first()).not.toBeNull();
  await handleScheduled({ ...env, DESTINATIONS_MODE: 'on' } as Env);
  expect(spy).toHaveBeenCalledTimes(1);
});

it('on ignores channel hints, schedules failure, and retries through cron', async () => {
  const spy = vi.spyOn(adapter, 'deliverToChannelWithOptions').mockRejectedValueOnce(new Error('temporary failure'))
    .mockResolvedValue({ delivered: true, telegramMessageId: 123 });
  const id = await send('on');
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1].chat_id).toBe('new-chat');
  expect(await env.DB.prepare('SELECT status, attempts FROM message_deliveries WHERE message_id = ?').bind(id).first())
    .toEqual({ status: 'failed', attempts: 1 });
  await env.DB.prepare("UPDATE message_deliveries SET next_attempt_at = '2000-01-01' WHERE message_id = ?").bind(id).run();
  await handleScheduled({ ...env, DESTINATIONS_MODE: 'on' } as Env);
  expect(spy).toHaveBeenCalledTimes(2);
  expect(await env.DB.prepare('SELECT status, attempts, external_message_id, next_attempt_at FROM message_deliveries WHERE message_id = ?').bind(id).first())
    .toEqual({ status: 'sent', attempts: 2, external_message_id: '123', next_attempt_at: null });
});
it('shadow records matching destinations without a disagreement audit', async () => {
  await env.DB.prepare("UPDATE channel_configs SET config = json_set(config, '$.chat_id', 'new-chat') WHERE agent_id = 'test-agent-id'").run();
  const spy = vi.spyOn(adapter, 'deliverToChannelWithOptions').mockResolvedValue({ delivered: true });
  const id = await send('shadow');
  expect(spy).toHaveBeenCalledTimes(1);
  expect(await env.DB.prepare('SELECT status FROM message_deliveries WHERE message_id = ?').bind(id).first()).toEqual({ status: 'queued' });
  expect(await env.DB.prepare("SELECT id FROM audit_log WHERE action = 'destination_shadow' AND resource_id = ?").bind(id).first()).toBeNull();
});
