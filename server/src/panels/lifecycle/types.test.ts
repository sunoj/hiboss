// Pure lifecycle deadline tests for the shared expiry contract.
// Exports no runtime values.
// Dependencies: lifecycle deadline helper and Vitest.

import { describe, expect, it } from 'vitest';
import { deriveExpiresAt } from './types';

describe('panel expiry derivation', () => {
  it('uses creation time before the first observation', () => {
    expect(deriveExpiresAt('2026-09-09T00:00:00.000Z', null, 3600)).toBe('2026-09-09T01:00:00.000Z');
  });

  it('uses the last observation time after an observation', () => {
    expect(deriveExpiresAt('2026-09-09T00:00:00.000Z', '2026-09-09T02:00:00.000Z', 60)).toBe('2026-09-09T02:01:00.000Z');
  });
});
