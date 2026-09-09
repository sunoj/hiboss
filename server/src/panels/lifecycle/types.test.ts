// Pure lifecycle deadline tests for the shared expiry contract.
// Exports no runtime values.
// Dependencies: lifecycle deadline helper and Vitest.

import { describe, expect, it } from 'vitest';
import { DEFAULT_TTL_SECONDS, MAX_TTL_SECONDS, MIN_TTL_SECONDS } from './types';

describe('panel expiry policy', () => {
  it('keeps the declared ttl bounds and default', () => {
    expect(DEFAULT_TTL_SECONDS).toBe(3600);
    expect([MIN_TTL_SECONDS, MAX_TTL_SECONDS]).toEqual([60, 604800]);
  });
});
