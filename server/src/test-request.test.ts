// Calibrates shared JSON reads against real Response bodies and request failures.
// Verifies exact status enforcement, read ordering and unchanged error propagation.
// Depends on Vitest and the shared Worker request helpers.

import { describe, expect, it } from 'vitest';
import { testJson } from './test-request';

describe('testJson', () => {
  it.each([200, 201, 422])('reads JSON for expected status %i', async (status) => {
    const response = new Response('{"value":7}', { status });
    expect(await testJson(status, Promise.resolve(response))).toEqual({ value: 7 });
    expect(response.bodyUsed).toBe(true);
  });

  it('rejects a wrong status before consuming a valid body', async () => {
    const response = new Response('{"value":7}', { status: 503 });
    await expect(testJson(201, response)).rejects.toMatchObject({
      name: 'AssertionError', actual: 503, expected: 201,
    });
    expect(response.bodyUsed).toBe(false);
  });

  it('propagates malformed JSON after a matching status', async () => {
    const response = new Response('{invalid', { status: 200 });
    await expect(testJson(200, response)).rejects.toMatchObject({ name: 'SyntaxError' });
    expect(response.bodyUsed).toBe(true);
  });

  it('preserves request rejection identity', async () => {
    const failure = new Error('request failed');
    await expect(testJson(200, Promise.reject(failure))).rejects.toBe(failure);
  });
});
