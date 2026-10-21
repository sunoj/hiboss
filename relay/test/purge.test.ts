// Scheduled purge tests: unused registrations after 90 days and expired rate counters.

import { createExecutionContext, createScheduledController, env, waitOnExecutionContext } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import worker from '../src/index';
import { DAY_MS } from '../src/limits';
import { FIXED_NOW, TOKEN_A, TOKEN_B, call, countRows, mockApns, pushBody, register, relayEnv, resetDb } from './helpers';

beforeEach(async () => {
  await resetDb();
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(FIXED_NOW);
});
afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

async function runCron(): Promise<void> {
  const ctx = createExecutionContext();
  await worker.scheduled(createScheduledController(), await relayEnv(), ctx);
  await waitOnExecutionContext(ctx);
}

describe('scheduled purge', () => {
  it('deletes registrations unused for 90 days and keeps ones used since', async () => {
    mockApns();
    const stale = await register(TOKEN_A);
    const active = await register(TOKEN_B);
    vi.setSystemTime(FIXED_NOW + 60 * DAY_MS);
    expect((await call('POST', '/v1/push', { body: pushBody(active.handle) })).status).toBe(202);
    vi.setSystemTime(FIXED_NOW + 90 * DAY_MS + 1);
    await runCron();
    expect(await countRows('registrations')).toBe(1);
    expect((await call('POST', '/v1/push', { body: pushBody(stale.handle) })).status).toBe(410);
    expect((await call('POST', '/v1/push', { body: pushBody(active.handle) })).status).toBe(202);
  });

  it('keeps a registration exactly 90 days old', async () => {
    await register();
    vi.setSystemTime(FIXED_NOW + 90 * DAY_MS);
    await runCron();
    expect(await countRows('registrations')).toBe(1);
  });

  it('counts token rotation as use', async () => {
    const { deviceSecret } = await register(TOKEN_A);
    vi.setSystemTime(FIXED_NOW + 80 * DAY_MS);
    const body = { apnsToken: TOKEN_B, environment: 'production' };
    expect((await call('PUT', '/v1/registrations/self', { body, secret: deviceSecret })).status).toBe(204);
    vi.setSystemTime(FIXED_NOW + 100 * DAY_MS);
    await runCron();
    expect(await countRows('registrations')).toBe(1);
  });

  it('removes expired rate counters and keeps live ones', async () => {
    await register();
    expect(await countRows('rate_counters')).toBe(1);
    vi.setSystemTime(FIXED_NOW + DAY_MS);
    await register(TOKEN_B);
    await runCron();
    expect(await countRows('rate_counters')).toBe(1);
  });
});
