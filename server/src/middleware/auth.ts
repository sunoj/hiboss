// Middleware that enforces API key authentication and related helpers.
// Exports agent auth, boss auth, dual auth, hashing, and context helpers.
// Depends on Hono context types and the shared Env definition.

import { Context, Next } from 'hono';
import type { Env } from '../types';

type AuthContext = Context<{ Bindings: Env }> & {
  agentId?: string;
  bossId?: string;
  bossRole?: string;
  bossName?: string;
};

export async function hashApiKey(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export function getAgentId(c: Context<{ Bindings: Env }>): string {
  const ctx = c as AuthContext;
  if (!ctx.agentId) {
    throw new Error('agent context missing');
  }
  return ctx.agentId;
}

export function getBossId(c: Context<{ Bindings: Env }>): string {
  const ctx = c as AuthContext;
  if (!ctx.bossId) {
    throw new Error('boss context missing');
  }
  return ctx.bossId;
}

export function getBossRole(c: Context<{ Bindings: Env }>): string {
  return (c as AuthContext).bossRole ?? 'viewer';
}

export function getBossName(c: Context<{ Bindings: Env }>): string {
  return (c as AuthContext).bossName ?? 'boss';
}

/** Extract bearer token from Authorization header. */
function extractToken(c: Context<{ Bindings: Env }>): string | null {
  const header = c.req.header('authorization') ?? c.req.header('Authorization');
  if (!header?.toLowerCase().startsWith('bearer ')) return null;
  const token = header.slice(7).trim();
  return token || null;
}

/** Agent-only authentication: requires an api_keys token. */
export async function apiAuth(c: AuthContext, next: Next): Promise<Response | void> {
  const token = extractToken(c);
  if (!token) return c.text('Unauthorized', 401);
  const keyHash = await hashApiKey(token);
  const record = await c.env.DB.prepare('SELECT id FROM api_keys WHERE key_hash = ?').bind(keyHash).first<{ id: string }>();
  if (!record) return c.text('Unauthorized', 401);
  c.agentId = record.id;
  await c.env.DB.prepare("UPDATE api_keys SET last_used_at = datetime('now') WHERE id = ?").bind(record.id).run();
  return next();
}

/** Boss-only authentication: requires a boss token. */
export async function bossAuth(c: AuthContext, next: Next): Promise<Response | void> {
  const token = extractToken(c);
  if (!token) return c.text('Unauthorized', 401);
  const keyHash = await hashApiKey(token);
  const boss = await c.env.DB
    .prepare('SELECT id, name, role FROM bosses WHERE token_hash = ?')
    .bind(keyHash)
    .first<{ id: string; name: string; role: string }>();
  if (!boss) return c.text('Unauthorized', 401);
  c.bossId = boss.id;
  c.bossRole = boss.role;
  c.bossName = boss.name;
  return next();
}

/** Dual auth: accepts either agent or boss token. Sets appropriate context. */
export async function dualAuth(c: AuthContext, next: Next): Promise<Response | void> {
  const token = extractToken(c);
  if (!token) return c.text('Unauthorized', 401);
  const keyHash = await hashApiKey(token);
  // Try agent first
  const agent = await c.env.DB.prepare('SELECT id FROM api_keys WHERE key_hash = ?').bind(keyHash).first<{ id: string }>();
  if (agent) {
    c.agentId = agent.id;
    await c.env.DB.prepare("UPDATE api_keys SET last_used_at = datetime('now') WHERE id = ?").bind(agent.id).run();
    return next();
  }
  // Try boss
  const boss = await c.env.DB
    .prepare('SELECT id, name, role FROM bosses WHERE token_hash = ?')
    .bind(keyHash)
    .first<{ id: string; name: string; role: string }>();
  if (boss) {
    c.bossId = boss.id;
    c.bossRole = boss.role;
    c.bossName = boss.name;
    return next();
  }
  return c.text('Unauthorized', 401);
}

/** Check if current context is boss-authenticated. */
export function isBossAuth(c: Context<{ Bindings: Env }>): boolean {
  return !!(c as AuthContext).bossId;
}
