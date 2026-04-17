// Tests for request id tracing middleware behavior.
// Verifies generated, echoed, and rejected request ids on responses.
// Depends on Hono, Vitest, and the requestId middleware.

import { Hono } from 'hono';
import { describe, expect, it } from 'vitest';
import { requestId } from './request-id';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function buildApp(): Hono<{ Variables: { reqId: string } }> {
  const app = new Hono<{ Variables: { reqId: string } }>();
  app.use('*', requestId);
  app.get('/echo', (c) => c.json({ request_id: c.get('reqId') }));
  return app;
}

describe('requestId middleware', () => {
  it('generates a UUID when no request id header is sent', async () => {
    const res = await buildApp().request('/echo');
    const reqId = res.headers.get('x-request-id');
    const body = await res.json() as { request_id: string };

    expect(reqId).toMatch(UUID_PATTERN);
    expect(body.request_id).toBe(reqId);
  });

  it('echoes a valid request id header', async () => {
    const res = await buildApp().request('/echo', {
      headers: { 'x-request-id': 'agent.123_REQ-id' },
    });

    expect(res.headers.get('x-request-id')).toBe('agent.123_REQ-id');
  });

  it('generates a UUID when request id contains invalid characters', async () => {
    const res = await buildApp().request('/echo', {
      headers: { 'x-request-id': 'bad id!' },
    });
    const reqId = res.headers.get('x-request-id');

    expect(reqId).toMatch(UUID_PATTERN);
    expect(reqId).not.toBe('bad id!');
  });
});
