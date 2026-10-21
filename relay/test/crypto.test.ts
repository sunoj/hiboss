// Unit tests for capability minting, hashing and constant-time comparison.

import { describe, expect, it } from 'vitest';
import { constantTimeEqual, randomToken, sha256Hex } from '../src/crypto';

describe('crypto helpers', () => {
  it('mints distinct 43-character base64url tokens', () => {
    const tokens = new Set(Array.from({ length: 50 }, randomToken));
    expect(tokens.size).toBe(50);
    for (const token of tokens) expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it('hashes with SHA-256 hex', async () => {
    expect(await sha256Hex('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  it('compares equal, unequal and different-length values', () => {
    expect(constantTimeEqual('a'.repeat(64), 'a'.repeat(64))).toBe(true);
    expect(constantTimeEqual('a'.repeat(64), 'a'.repeat(63) + 'b')).toBe(false);
    expect(constantTimeEqual('a'.repeat(64), 'a'.repeat(63))).toBe(false);
  });
});
