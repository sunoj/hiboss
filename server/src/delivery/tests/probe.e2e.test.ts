// Authenticated notification probes enforce mode, ownership, and credential secrecy.
// Depends on real Worker routing and D1 with mocked destination adapters.
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, afterEach, expect, it, vi } from 'vitest';
import app from '../../index';
import { seedDatabase, seedBossToken } from '../../test-helpers';
import * as push from '../../apns';
import { liveTokenId } from '../../push/resolution-test-support';
beforeAll(async () => {
  await seedDatabase();
  for (const role of ['admin', 'manager', 'viewer']) await seedBossToken(role, role, `probe-${role}`, `probe-${role}`);
  await env.DB.prepare(`INSERT INTO boss_devices (id, boss_id, device_token, bundle_id, environment, token_id)
    VALUES ('probe-device', 'probe-manager', 'probe-token', 'app', 'sandbox', ?)`)
    .bind(await liveTokenId('probe-manager')).run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, target, label) VALUES ('probe-d', 'probe-manager', 'apns', '{\"device_id\":\"probe-device\"}', 'Push')").run();
});
afterEach(() => vi.restoreAllMocks());
async function request(role: string, mode?: string, path = 'destinations/probe-d/test', method = 'POST'): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request(`https://test/api/boss/${path}`, { method, headers: { Authorization: `Bearer probe-${role}` } }), { ...env, DESTINATIONS_MODE: mode }, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
it.each([undefined, 'off', 'shadow', 'invalid'])('never probes in mode %s', async mode => {
  const spy = vi.spyOn(push, 'sendPush');
  expect((await request('manager', mode)).status).toBe(409);
  expect(spy).not.toHaveBeenCalled();
});
it('returns cross-boss 404 and viewer 403 before sending', async () => {
  const spy = vi.spyOn(push, 'sendPush');
  expect((await request('admin', 'on')).status).toBe(404);
  expect((await request('viewer', 'on')).status).toBe(403);
  expect(spy).not.toHaveBeenCalled();
});
it('probes the owned target in on mode without touching messages', async () => {
  vi.spyOn(push, 'hasApnsConfig').mockReturnValue(true);
  const before = await env.DB.prepare('SELECT COUNT(*) AS total FROM messages').first();
  const spy = vi.spyOn(push, 'sendPush').mockResolvedValue({ ok: true, prune: false });
  expect(await (await request('manager', 'on')).json()).toEqual({ ok: true, external_message_id: null });
  expect(spy).toHaveBeenCalledTimes(1);
  expect(spy.mock.calls[0][1]).toBe('probe-token');
  expect(await env.DB.prepare('SELECT COUNT(*) AS total FROM messages').first()).toEqual(before);
});
