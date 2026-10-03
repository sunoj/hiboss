// Verifies publication-only questionnaire pushes through authenticated HTTP.
// Covers payloads, preferences, retry races, device pruning, and delivery failures.
// Dependencies: real Worker/D1 fixtures and mocked APNs delivery.

import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, expect, it, vi } from 'vitest';
import app from '../../../index';
import * as apns from '../../../apns';
import { authHeaders } from '../../../test-helpers';
import type { Env } from '../../../types';
import { base, BOSS, finish, publishPanel, questionnaire, setup } from './support';

const pushEnv: Env = { ...env, APNS_KEY_ID: 'test-key', APNS_TEAM_ID: 'test-team', APNS_AUTH_KEY: 'mocked' };
beforeAll(setup);
beforeEach(async () => {
  vi.spyOn(apns, 'sendPush').mockResolvedValue({ ok: true, prune: false });
  await env.DB.prepare('UPDATE bosses SET preferences = NULL WHERE id = ?').bind(BOSS).run();
  await env.DB.prepare('INSERT OR REPLACE INTO boss_devices (id, boss_id, device_token, bundle_id, environment) VALUES (?, ?, ?, ?, ?)')
    .bind('questionnaire-device', BOSS, 'request-token', 'com.hiboss.ios', 'sandbox').run();
});
afterEach(() => vi.restoreAllMocks());

async function request(path: string, body: unknown, method = 'POST', key = crypto.randomUUID(), bindings = pushEnv): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await app.fetch(new Request(`${base}/${path}`, {
    method, headers: { ...authHeaders(), 'Idempotency-Key': key }, body: JSON.stringify(body),
  }), bindings, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}
async function publish(form = questionnaire, bindings = pushEnv): Promise<{ panelId: string; requestId: string }> {
  const panelId = await publishPanel();
  const response = await request(`panels/${panelId}/requests`, form, 'POST', crypto.randomUUID(), bindings);
  expect(response.status).toBe(201);
  const receipt = await response.json() as { requestId: string; requestRevision: number };
  expect(receipt).toEqual({ requestId: expect.any(String), requestRevision: 1 });
  return { panelId, requestId: receipt.requestId };
}
async function preferences(value: Record<string, unknown>): Promise<void> {
  await env.DB.prepare('UPDATE bosses SET preferences = ? WHERE id = ?').bind(JSON.stringify(value), BOSS).run();
}

it('calls sendPush exactly once for a fresh blocking publish with the request contract', async () => {
  const { panelId, requestId } = await publish();
  expect(apns.sendPush).toHaveBeenCalledExactlyOnceWith(expect.anything(), 'request-token', 'sandbox', 'com.hiboss.ios', {
    aps: { alert: { title: 'test-agent needs input', subtitle: 'Questionnaire', body: questionnaire.title },
      category: 'HIBOSS_REQUEST', 'thread-id': BOSS, 'interruption-level': 'active', sound: 'default' },
    category: 'HIBOSS_REQUEST', panelId, requestId, agentName: 'test-agent', priority: 'normal',
  }, '10');
});
it('never calls sendPush for blocking:false', async () => {
  await publish({ ...questionnaire, blocking: false });
  expect(apns.sendPush).not.toHaveBeenCalled();
});
it('keeps sendPush at one call after an idempotent retry', async () => {
  const panelId = await publishPanel(), key = crypto.randomUUID();
  const first = await request(`panels/${panelId}/requests`, questionnaire, 'POST', key);
  const retry = await request(`panels/${panelId}/requests`, questionnaire, 'POST', key);
  expect(first.status).toBe(201);
  expect(retry.status).toBe(201);
  expect(await retry.json()).toEqual(await first.json());
  expect(apns.sendPush).toHaveBeenCalledTimes(1);
});
it('pushes only the insert winner when publications race', async () => {
  const panelId = await publishPanel(), key = crypto.randomUUID();
  const responses = await Promise.all([1, 2].map(() => request(`panels/${panelId}/requests`, questionnaire, 'POST', key)));
  expect(responses.map(response => response.status)).toEqual([201, 201]);
  expect(await responses[0].json()).toEqual(await responses[1].json());
  expect(apns.sendPush).toHaveBeenCalledTimes(1);
});
it('never calls sendPush for replace or withdraw', async () => {
  const { requestId } = await publish({ ...questionnaire, blocking: false });
  expect((await request(`interaction-requests/${requestId}`, { ...questionnaire, expectedRevision: 1 }, 'PUT')).status).toBe(200);
  expect((await request(`interaction-requests/${requestId}/withdraw`, { expectedRevision: 2, reason: 'Finished' })).status).toBe(200);
  expect(apns.sendPush).not.toHaveBeenCalled();
});
it('never calls sendPush when the boss sets deliver:false', async () => {
  await preferences({ push: { normal: { deliver: false } } });
  await publish();
  expect(apns.sendPush).not.toHaveBeenCalled();
});
it('uses a private body without changing the request routing fields', async () => {
  await preferences({ private_push: true });
  const { panelId, requestId } = await publish();
  expect(apns.sendPush).toHaveBeenCalledTimes(1);
  expect(vi.mocked(apns.sendPush).mock.calls[0][4]).toEqual({
    aps: { alert: { title: 'test-agent needs input', subtitle: 'Questionnaire', body: 'Needs input' },
      category: 'HIBOSS_REQUEST', 'thread-id': BOSS, 'interruption-level': 'active', sound: 'default' },
    category: 'HIBOSS_REQUEST', panelId, requestId, agentName: 'test-agent', priority: 'normal',
  });
});
it.each(['low', 'high', 'critical'])('reuses the decision tier for %s priority', async priority => {
  await publish({ ...questionnaire, priority });
  expect(apns.sendPush).toHaveBeenCalledTimes(1);
  expect(vi.mocked(apns.sendPush).mock.calls[0].slice(4)).toEqual([
    expect.objectContaining({ priority, aps: expect.objectContaining({ sound: 'default',
      'interruption-level': priority === 'critical' ? 'time-sensitive' : 'active' }) }), '10',
  ]);
});
it.each([{ decision_alerts: false }, { push: { normal: { sound: false, level: 'passive' } } }])('honors quiet tier preferences %j', async prefs => {
  await preferences(prefs);
  await publish();
  expect(apns.sendPush).toHaveBeenCalledTimes(1);
  const call = vi.mocked(apns.sendPush).mock.calls[0];
  expect(call[4].aps['interruption-level']).toBe('passive');
  expect(call[4].aps.sound).toBeUndefined();
  expect(call[5]).toBe('5');
});
it.each(['off', 'shadow', 'on'])('follows the boss-device suppression rule in %s mode', async mode => {
  await publish(questionnaire, { ...pushEnv, DESTINATIONS_MODE: mode });
  expect(apns.sendPush).toHaveBeenCalledTimes(mode === 'on' ? 0 : 1);
});
it('publishes without pushing when APNs is not configured', async () => {
  await publish(questionnaire, { ...pushEnv, APNS_AUTH_KEY: undefined });
  expect(apns.sendPush).not.toHaveBeenCalled();
});
it('does not push if the insert creates no row on an ended panel', async () => {
  const panelId = await publishPanel();
  expect((await finish(panelId)).status).toBe(200);
  expect((await request(`panels/${panelId}/requests`, questionnaire)).status).toBe(409);
  expect(apns.sendPush).not.toHaveBeenCalled();
});
it('keeps publication successful after a push failure', async () => {
  vi.mocked(apns.sendPush).mockRejectedValue(new Error('APNs unavailable'));
  await publish();
  expect(apns.sendPush).toHaveBeenCalledTimes(1);
});
it('prunes invalid devices and their destinations and still pushes the other target device', async () => {
  await env.DB.prepare("INSERT INTO bosses (id, name, role) VALUES ('other-request-boss', 'Other boss', 'admin')").run();
  await env.DB.prepare(`INSERT INTO boss_devices (id, boss_id, device_token, bundle_id, environment) VALUES
    ('other-request-device', 'other-request-boss', 'other-token', 'app', 'sandbox'),
    ('second-request-device', ?, 'second-token', 'app', 'production')`).bind(BOSS).run();
  await env.DB.prepare(`INSERT INTO boss_destinations (id, boss_id, kind, target, label)
    VALUES ('request-destination', ?, 'apns', '{"device_id":"questionnaire-device"}', 'Phone')`).bind(BOSS).run();
  vi.mocked(apns.sendPush).mockImplementation(async (_env, token) => token === 'request-token'
    ? { ok: false, prune: true, reason: 'BadDeviceToken' } : { ok: true, prune: false });
  await publish();
  expect(apns.sendPush).toHaveBeenCalledTimes(2);
  expect(vi.mocked(apns.sendPush).mock.calls.map(call => call[1]).sort()).toEqual(['request-token', 'second-token']);
  expect(await env.DB.prepare("SELECT id FROM boss_devices WHERE id = 'questionnaire-device'").first()).toBeNull();
  expect(await env.DB.prepare("SELECT id FROM boss_destinations WHERE id = 'request-destination'").first()).toBeNull();
});
