// Sends integration-test requests through the real Worker service binding.
// Exports testRequest and returnsStatus, preserving explicit requests and per-case assertions.
// Dependencies: cloudflare:test SELF and Vitest; no default authorization or content type.

import { SELF } from 'cloudflare:test';
import { expect } from 'vitest';

export function testRequest(
  method: string,
  url: string,
  headers: RequestInit['headers'],
  json?: unknown,
): Promise<Response> {
  return SELF.fetch(url, { method, headers, body: JSON.stringify(json) });
}

export function returnsStatus(
  status: number,
  request: () => Promise<{ status: number }>,
): () => Promise<void> {
  return async () => {
    const response = await request();
    expect(response.status).toBe(status);
  };
}
