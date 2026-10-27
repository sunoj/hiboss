// Live Activity token registration tests: auth, validation, 404 for unreadable asks, 409 outside
// direct mode or for a closed ask, upsert per device and ask, deletion with the device or its move.
// Calls the boss devices router with a direct-mode env; tokens are fake fixtures.
import { testRequest } from '../test-request';
import { createExecutionContext, env, SELF, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { seedBossToken, seedDatabase } from '../test-helpers';
import { apnsEnv, insertAsk, seedAudience } from '../push/resolution-test-support';
import { bossDevicesRouter } from './boss-devices';
import type { Env } from '../types';

const TOKEN = `hb_boss_live_activity_${'cd'.repeat(8)}`;
const RELAY_TOKEN = `hb_boss_live_activity_relay_${'ef'.repeat(8)}`;
const BOSS = 'la-reg-boss';
let direct: Env;

beforeAll(async () => {
  await seedDatabase();
  direct = await apnsEnv();
  await seedBossToken('LA boss', 'manager', TOKEN, BOSS);
  const { agentId } = await seedAudience('la-reg', { token: 'dd01' });
  await insertAsk('la-reg-ask', agentId);
  await insertAsk('la-reg-closed', agentId, { status: 'replied' });
  await insertAsk('la-reg-moved', agentId);
  await seedAudience('la-other', { token: 'dd02' });
  await insertAsk('la-other-ask', 'la-other-agent');
  await seedBossToken('LA relay boss', 'manager', RELAY_TOKEN, 'la-relay-boss');
  const relay = await seedAudience('la-relay', { token: '', relay: true });
  await insertAsk('la-relay-ask', relay.agentId);
});
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

async function register(body: unknown, target: Env = direct, token = TOKEN): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await bossDevicesRouter.fetch(new Request('https://test/live-activities', {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify(body) }), target, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

const valid = { messageId: 'la-reg-ask', activityToken: 'AB'.repeat(32), environment: 'production' };

async function storedTokens(messageId: string): Promise<string[]> {
  const rows = await env.DB.prepare('SELECT activity_token FROM live_activity_tokens WHERE message_id = ?')
    .bind(messageId).all<{ activity_token: string }>();
  return rows.results.map((row) => row.activity_token);
}

describe('POST /api/boss/devices/live-activities', () => {
  it('requires boss authentication', async () => {
    expect((await register(valid, direct, 'hb_boss_unknown_token')).status).toBe(401);
  });

  it('answers 409 outside direct mode', async () => {
    const response = await testRequest('POST', 'https://test/api/boss/devices/live-activities',
      { Authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' }, valid);
    expect(response.status).toBe(409);
    expect(await storedTokens('la-reg-ask')).toEqual([]);
  });

  it.each([
    ['a non-hex token', { activityToken: 'zz'.repeat(32) }],
    ['an odd-length token', { activityToken: 'abc' }],
    ['a token over 200 characters', { activityToken: 'ab'.repeat(101) }],
    ['an empty token', { activityToken: '' }],
    ['an unknown environment', { environment: 'staging' }],
    ['a missing message id', { messageId: undefined }],
  ])('rejects %s with 400', async (_name, extra) => {
    expect((await register({ ...valid, ...extra })).status).toBe(400);
  });

  it('answers 404 for a message the boss cannot read or that does not exist', async () => {
    expect((await register({ ...valid, messageId: 'la-other-ask' })).status).toBe(404);
    expect((await register({ ...valid, messageId: 'la-missing-ask' })).status).toBe(404);
  });

  it('answers 409 when the boss has no direct push device', async () => {
    expect((await register({ ...valid, messageId: 'la-relay-ask' }, direct, RELAY_TOKEN)).status).toBe(409);
  });

  it('answers 409 and stores nothing for an ask that is no longer open', async () => {
    expect((await register({ ...valid, messageId: 'la-reg-closed' })).status).toBe(409);
    expect(await storedTokens('la-reg-closed')).toEqual([]);
  });

  it('upserts one row per device and ask, then deletes it with the device', async () => {
    expect((await register(valid)).status).toBe(204);
    expect((await register({ ...valid, activityToken: 'cd'.repeat(40) })).status).toBe(204);
    expect(await storedTokens('la-reg-ask')).toEqual(['cd'.repeat(40)]);
    const removed = await SELF.fetch('https://test/api/boss/devices/dd01', {
      method: 'DELETE', headers: { Authorization: `Bearer ${TOKEN}` } });
    expect(removed.status).toBe(200);
    expect(await storedTokens('la-reg-ask')).toEqual([]);
  });

  it('drops the tokens of a device registered again under another boss', async () => {
    // Runs after the upsert test removed dd01, so dd03 is this boss's only direct device.
    const device = { token: 'dd03', bundleId: 'ai.hiboss.app', environment: 'sandbox', platform: 'ios' };
    const registerDevice = (token: string) => testRequest('POST', 'https://test/api/boss/devices',
      { Authorization: `Bearer ${token}`, 'content-type': 'application/json' }, device);
    expect((await registerDevice(TOKEN)).status).toBe(200);
    expect((await register({ ...valid, messageId: 'la-reg-moved' })).status).toBe(204);
    expect(await storedTokens('la-reg-moved')).toHaveLength(1);
    expect(await (await registerDevice(RELAY_TOKEN)).json()).toEqual({ ok: true, reparented: true });
    expect(await storedTokens('la-reg-moved')).toEqual([]);
  });
});
