// Middleware that enforces API key authentication and related helpers.
// Exports agent auth, boss auth, dual auth, hashing, and context helpers.
// Depends on Hono context types and the shared Env definition.

import { Context, Next } from 'hono';
import type { Env } from '../types';
import type { ClientId } from '../boss-clients/types';

type AuthContext = Context<{ Bindings: Env }> & {
  agentId?: string;
  bossId?: string;
  bossTokenId?: string;
  clientId?: ClientId | null;
  bossRole?: string;
  bossName?: string;
};

export async function hashApiKey(token: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

/** Constant-time string comparison; avoids leaking secret length-prefix via timing. */
export function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aBytes = enc.encode(a);
  const bBytes = enc.encode(b);
  if (aBytes.length !== bBytes.length) return false;
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) diff |= aBytes[i] ^ bBytes[i];
  return diff === 0;
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

export function getBossTokenId(c: Context<{ Bindings: Env }>): string {
  const ctx = c as AuthContext;
  if (!ctx.bossTokenId) {
    throw new Error('boss token context missing');
  }
  return ctx.bossTokenId;
}

export function getClientId(c: Context<{ Bindings: Env }>): ClientId | null {
  return (c as AuthContext).clientId ?? null;
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
  c.executionCtx.waitUntil(
    c.env.DB.prepare("UPDATE api_keys SET last_used_at = datetime('now') WHERE id = ?").bind(record.id).run(),
  );
  return next();
}

/** Boss-only authentication: requires a boss token. */
export async function bossAuth(c: AuthContext, next: Next): Promise<Response | void> {
  const token = extractToken(c);
  if (!token) return c.text('Unauthorized', 401);
  const keyHash = await hashApiKey(token);
  if (!await resolveBossAuth(c, keyHash)) return c.text('Unauthorized', 401);
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
    c.executionCtx.waitUntil(
      c.env.DB.prepare("UPDATE api_keys SET last_used_at = datetime('now') WHERE id = ?").bind(agent.id).run(),
    );
    return next();
  }
  if (await resolveBossAuth(c, keyHash)) return next();
  return c.text('Unauthorized', 401);
}

/** Check if current context is boss-authenticated. */
export function isBossAuth(c: Context<{ Bindings: Env }>): boolean {
  return !!(c as AuthContext).bossId;
}

// Read the client timestamp with authentication; conditional SQL also guards concurrent isolates.
async function resolveBossAuth(c: AuthContext, keyHash: string): Promise<boolean> {
  const boss = await c.env.DB.prepare(`SELECT b.id, b.name, b.role, bt.id AS token_id,
    bt.client_id, bc.last_seen_at FROM boss_tokens bt JOIN bosses b ON b.id = bt.boss_id
    LEFT JOIN boss_clients bc ON bc.id = bt.client_id
    WHERE bt.token_hash = ? AND bt.revoked_at IS NULL AND bc.revoked_at IS NULL`)
    .bind(keyHash).first<{ id: string; name: string; role: string; token_id: string;
      client_id: ClientId | null; last_seen_at: string | null }>();
  if (!boss) return false;
  c.executionCtx.waitUntil(c.env.DB.prepare(
    "UPDATE boss_tokens SET last_used_at = datetime('now') WHERE id = ?",
  ).bind(boss.token_id).run());
  const lastSeen = boss.last_seen_at ? Date.parse(boss.last_seen_at.replace(' ', 'T') + 'Z') : 0;
  if (boss.client_id && Date.now() - lastSeen >= 60_000) {
    c.executionCtx.waitUntil(c.env.DB.prepare(`UPDATE boss_clients SET last_seen_at = datetime('now')
      WHERE id = ? AND revoked_at IS NULL
      AND (last_seen_at IS NULL OR last_seen_at <= datetime('now', '-1 minute'))`)
      .bind(boss.client_id).run());
  }
  c.bossId = boss.id;
  c.bossTokenId = boss.token_id;
  c.clientId = boss.client_id;
  c.bossRole = boss.role;
  c.bossName = boss.name;
  return true;
}
