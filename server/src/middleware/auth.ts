// Middleware that enforces API key authentication and related helpers.
// Exports the bearer auth guard, hashing helper, and agent lookup util.
// Depends on Hono context types and the shared Env definition.

import { Context, Next } from 'hono';
import type { Env } from '../types';

type AgentContext = Context<{ Bindings: Env }> & { agentId?: string };

export async function hashApiKey(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export function getAgentId(c: Context<{ Bindings: Env }>): string {
  const agentContext = c as AgentContext;
  if (!agentContext.agentId) {
    throw new Error('agent context missing');
  }
  return agentContext.agentId;
}

export async function apiAuth(c: AgentContext, next: Next): Promise<Response | void> {
  const header = c.req.header('authorization') ?? c.req.header('Authorization');
  if (!header?.toLowerCase().startsWith('bearer ')) {
    return c.text('Unauthorized', 401);
  }
  const token = header.slice(7).trim();
  if (!token) {
    return c.text('Unauthorized', 401);
  }
  const keyHash = await hashApiKey(token);
  const record = await c.env.DB.prepare('SELECT id FROM api_keys WHERE key_hash = ?').bind(keyHash).first<{ id: string }>();
  if (!record) {
    return c.text('Unauthorized', 401);
  }
  c.agentId = record.id;
  await c.env.DB.prepare("UPDATE api_keys SET last_used_at = datetime('now') WHERE id = ?").bind(record.id).run();
  return next();
}
