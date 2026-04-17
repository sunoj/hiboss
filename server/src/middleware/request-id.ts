// Middleware that assigns and echoes a stable request id for tracing.
// Exports the requestId Hono middleware for parent app registration.
// Depends on Hono middleware types and the shared Env definition.

import type { MiddlewareHandler } from 'hono';
import type { Env } from '../types';

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]+$/;

type RequestIdEnv = { Bindings: Env; Variables: { reqId: string } };

function sanitizeRequestId(value: string | undefined): string | null {
  const trimmed = value?.trim().slice(0, 128);
  if (!trimmed || !REQUEST_ID_PATTERN.test(trimmed)) {
    return null;
  }
  return trimmed;
}

export const requestId: MiddlewareHandler<RequestIdEnv> = async (c, next) => {
  const id = sanitizeRequestId(c.req.header('x-request-id')) ?? crypto.randomUUID();
  c.set('reqId', id);
  c.header('x-request-id', id);
  await next();
};
