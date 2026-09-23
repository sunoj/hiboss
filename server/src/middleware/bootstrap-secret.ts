// Shared authorization policy for all first-agent issuance paths.
import type { Context } from 'hono';
import type { Env } from '../types';
import { timingSafeEqual } from './auth';

export function hasValidBootstrapSecret(c: Context<{ Bindings: Env }>): boolean {
  const expectedSecret = c.env.BOOTSTRAP_SECRET;
  if (!expectedSecret) return true;
  const headerSecret = c.req.header('X-Bootstrap-Secret');
  if (headerSecret && timingSafeEqual(headerSecret, expectedSecret)) return true;
  const authorization = c.req.header('Authorization');
  const bearerPrefix = 'Bearer ';
  return authorization?.startsWith(bearerPrefix)
    ? timingSafeEqual(authorization.slice(bearerPrefix.length), expectedSecret)
    : false;
}
