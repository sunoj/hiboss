// Delivery level tests: priority, interruption level and sound are required and used verbatim.
// Kind selects only the loc-key; it never changes the APNs urgency.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { DELIVERY, call, mockApns, pushBody, register, resetDb } from './helpers';

beforeEach(resetDb);
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

async function sentRequest(extra: Record<string, unknown>) {
  const fetchMock = mockApns();
  const { handle } = await register();
  const response = await call('POST', '/v1/push', { body: pushBody(handle, extra) });
  expect(response.status).toBe(202);
  const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
  const payload = JSON.parse(init.body as string) as { aps: Record<string, unknown> };
  return { headers: init.headers as Record<string, string>, aps: payload.aps };
}

describe('POST /v1/push delivery level mapping', () => {
  it.each([
    [5, '5'],
    [10, '10'],
  ])('sends priority %s as apns-priority %s', async (priority, header) => {
    const { headers } = await sentRequest({ priority });
    expect(headers['apns-priority']).toBe(header);
  });

  it.each(['passive', 'active', 'time-sensitive'])('sends interruption %s as aps.interruption-level', async (level) => {
    const { aps } = await sentRequest({ interruption: level });
    expect(aps['interruption-level']).toBe(level);
  });

  it('sends sound true as aps.sound "default" and omits it for false', async () => {
    expect((await sentRequest({ sound: true })).aps.sound).toBe('default');
    expect((await sentRequest({ sound: false })).aps).not.toHaveProperty('sound');
  });

  it('does not derive priority from kind', async () => {
    expect((await sentRequest({ kind: 'decision', priority: 5 })).headers['apns-priority']).toBe('5');
    expect((await sentRequest({ kind: 'message', priority: 10 })).headers['apns-priority']).toBe('10');
  });

  it('sends a passive push silently at priority 5', async () => {
    const { headers, aps } = await sentRequest({ priority: 5, interruption: 'passive', sound: false });
    expect(headers['apns-priority']).toBe('5');
    expect(aps['interruption-level']).toBe('passive');
    expect(aps).not.toHaveProperty('sound');
    expect(aps.alert).toEqual({ 'title-loc-key': 'HIBOSS_PUSH_TITLE', 'loc-key': 'HIBOSS_PUSH_MESSAGE' });
  });
});

describe('POST /v1/push delivery level validation', () => {
  it.each(Object.keys(DELIVERY))('rejects a body without %s with 400 and sends nothing', async (field) => {
    const fetchMock = mockApns();
    const { handle } = await register();
    const body: Record<string, unknown> = pushBody(handle);
    delete body[field];
    expect((await call('POST', '/v1/push', { body })).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it.each([
    ['priority 1', { priority: 1 }],
    ['priority 7', { priority: 7 }],
    ['string priority', { priority: '10' }],
    ['null priority', { priority: null }],
    ['interruption critical', { interruption: 'critical' }],
    ['interruption with wrong case', { interruption: 'Passive' }],
    ['numeric interruption', { interruption: 1 }],
    ['string sound', { sound: 'default' }],
    ['numeric sound', { sound: 1 }],
    ['null sound', { sound: null }],
  ])('rejects %s with 400 and sends nothing', async (_name, extra) => {
    const fetchMock = mockApns();
    const { handle } = await register();
    expect((await call('POST', '/v1/push', { body: pushBody(handle, extra) })).status).toBe(400);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
