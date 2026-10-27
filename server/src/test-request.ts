// Sends integration-test requests through the real Worker service binding.
// Exports testRequest, preserving explicit headers and JSON serialization.
// Dependencies: cloudflare:test SELF; no default authorization or content type.

import { SELF } from 'cloudflare:test';

export function testRequest(
  method: string,
  url: string,
  headers: RequestInit['headers'],
  json?: unknown,
): Promise<Response> {
  return SELF.fetch(url, { method, headers, body: JSON.stringify(json) });
}
