// Authenticated notification probes enforce mode, ownership, and credential secrecy.
// Depends on real Worker routing and D1 with mocked destination adapters.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, afterEach, expect, it, vi } from 'vitest';
import app from '../../index';
import { seedDatabase, seedBossToken } from '../../test-helpers';
import * as adapter from '../../routes/delivery';
beforeAll(async () => {
  await seedDatabase();
  for (const role of ['admin', 'manager', 'viewer']) await seedBossToken(role, role, `probe-${role}`, `probe-${role}`);
  await env.DB.prepare("INSERT INTO channel_providers (id, provider, label, credentials) VALUES ('probe-p', 'telegram', 'Bot', '{\"bot_token\":\"secret\"}')").run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, provider_id, target, label) VALUES ('probe-d', 'probe-manager', 'telegram_chat', 'probe-p', '{\"chat_id\":\"123\"}', 'Chat')").run();
});
afterEach(() => vi.restoreAllMocks());
async function request(role: string, mode?: string, path = 'destinations/probe-d/test', method = 'POST'): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request(`https://test/api/boss/${path}`, { method, headers: { Authorization: `Bearer probe-${role}` } }), { ...env, DESTINATIONS_MODE: mode }, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
it.each([undefined, 'off', 'shadow', 'invalid'])('never probes in mode %s', async mode => {
  const spy = vi.spyOn(adapter, 'deliverToChannelWithOptions');
  expect((await request('manager', mode)).status).toBe(409);
  expect(spy).not.toHaveBeenCalled();
});
it('returns cross-boss 404 and viewer 403 before sending', async () => {
  const spy = vi.spyOn(adapter, 'deliverToChannelWithOptions');
  expect((await request('admin', 'on')).status).toBe(404);
  expect((await request('viewer', 'on')).status).toBe(403);
  expect(spy).not.toHaveBeenCalled();
});
it('probes the owned target in on mode without touching messages', async () => {
  const before = await env.DB.prepare('SELECT COUNT(*) AS total FROM messages').first();
  const spy = vi.spyOn(adapter, 'deliverToChannelWithOptions').mockResolvedValue({ delivered: true, telegramMessageId: 42 });
  expect(await (await request('manager', 'on')).json()).toEqual({ ok: true, external_message_id: '42' });
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1]).toMatchObject({ chat_id: '123', bot_token: 'secret' });
  expect(await env.DB.prepare('SELECT COUNT(*) AS total FROM messages').first()).toEqual(before);
});
it('provides safe provider choices for managers and sanitizes adapter errors', async () => {
  const inventory = await request('manager', 'shadow', 'destinations', 'GET');
  const text = await inventory.text();
  expect(text).toContain('"mode":"shadow"'); expect(text).toContain('"providers":[');
  expect(text).not.toContain('secret'); expect(text).not.toContain('credentials');
  vi.spyOn(adapter, 'deliverToChannelWithOptions').mockRejectedValue(new Error('secret'));
  const response = await request('manager', 'on');
  expect(response.status).toBe(502); expect(await response.text()).not.toContain('secret');
});
