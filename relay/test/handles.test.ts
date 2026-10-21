// Handle MAC tests: forged, garbled and non-canonical handles get the same 410 with no D1 access
// and no limiter call; a genuine handle meets the per-handle limiter before D1.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { sha256Hex } from '../src/crypto';
import { handleValid, mintHandle } from '../src/handles';
import {
  TEST_HANDLE_KEY,
  TOKEN_A,
  call,
  fakeLimiter,
  forbiddenDb,
  mockApns,
  pushBody,
  register,
  relayEnv,
  resetDb,
} from './helpers';

beforeEach(resetDb);
afterEach(() => vi.unstubAllGlobals());

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/** Same decoded bytes as `handle`, but with the unused low bits of the last character set. */
function nonCanonical(handle: string): string {
  const last = ALPHABET[ALPHABET.indexOf(handle[42]) | 1];
  return handle.slice(0, 42) + last;
}

function flipped(handle: string, index: number): string {
  const ch = handle[index] === 'A' ? 'B' : 'A';
  return handle.slice(0, index) + ch + handle.slice(index + 1);
}

describe('handle format', () => {
  it('mints distinct 43-character base64url handles that verify only under their key', async () => {
    const handles = await Promise.all(Array.from({ length: 20 }, () => mintHandle(TEST_HANDLE_KEY)));
    expect(new Set(handles).size).toBe(20);
    for (const handle of handles) {
      expect(handle).toMatch(/^[A-Za-z0-9_-]{43}$/);
      expect(await handleValid(TEST_HANDLE_KEY, handle)).toBe(true);
      expect(await handleValid('other-key', handle)).toBe(false);
      expect(await handleValid(TEST_HANDLE_KEY, nonCanonical(handle))).toBe(false);
    }
  });

  it('registration returns a handle carrying the MAC', async () => {
    mockApns();
    const { handle } = await register();
    expect(await handleValid(TEST_HANDLE_KEY, handle)).toBe(true);
  });
});

describe('POST /v1/push handle MAC', () => {
  it('answers forged and garbled handles 410 without D1 or limiter access', async () => {
    const fetchMock = mockApns();
    const relay = await relayEnv({ DB: forbiddenDb });
    const genuine = await mintHandle(TEST_HANDLE_KEY);
    const forged = [
      'A'.repeat(43),
      await mintHandle('other-key'),
      flipped(genuine, 0),
      flipped(genuine, 30),
      nonCanonical(genuine),
      genuine + 'A',
      genuine.slice(0, 42),
      '',
      '../../etc',
    ];
    for (const handle of forged) {
      const response = await call('POST', '/v1/push', { body: pushBody(handle), env: relay });
      expect(`${response.status} ${await response.text()}`).toBe('410 {"error":"gone"}');
    }
    expect((relay.HANDLE_RATE_LIMITER as ReturnType<typeof fakeLimiter>).keys).toEqual([]);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('answers a genuine handle over its 60/min rate 429 before D1', async () => {
    const fetchMock = mockApns();
    const limiter = fakeLimiter(false);
    const relay = await relayEnv({ DB: forbiddenDb, HANDLE_RATE_LIMITER: limiter });
    const handle = await mintHandle(TEST_HANDLE_KEY);
    const response = await call('POST', '/v1/push', { body: pushBody(handle), env: relay });
    expect(`${response.status} ${await response.text()}`).toBe('429 {"error":"rate_limited"}');
    expect(limiter.keys).toEqual([await sha256Hex(handle)]);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('answers a genuine but unregistered handle 410 after the lookup', async () => {
    mockApns();
    await register(TOKEN_A);
    const response = await call('POST', '/v1/push', { body: pushBody(await mintHandle(TEST_HANDLE_KEY)) });
    expect(response.status).toBe(410);
  });
});

describe('missing HANDLE_KEY', () => {
  it('answers registration and push 503 without D1 or APNs access', async () => {
    const fetchMock = mockApns();
    const relay = await relayEnv({ DB: forbiddenDb, HANDLE_KEY: undefined });
    const body = { apnsToken: TOKEN_A, environment: 'production' };
    const registration = await call('POST', '/v1/registrations', { body, env: relay });
    const push = await call('POST', '/v1/push', { body: pushBody(await mintHandle(TEST_HANDLE_KEY)), env: relay });
    expect([registration.status, push.status]).toEqual([503, 503]);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
