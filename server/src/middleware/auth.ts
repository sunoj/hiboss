// Middleware that enforces API key authentication and related helpers.
// Exports agent auth, boss auth, dual auth, hashing, and context helpers.
// Depends on Hono context types and the shared Env definition.

import { Context, Next } from 'hono';
import type { Env } from '../types';
import type { ClientId } from '../boss-clients/types';
import type { AgentKeyId } from '../agent-keys/types';

type AuthContext = Context<{ Bindings: Env }> & {
  agentId?: string;
  agentKeyId?: AgentKeyId | null;
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

export function getAgentKeyId(c: Context<{ Bindings: Env }>): AgentKeyId | null {
  return (c as AuthContext).agentKeyId ?? null;
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

/** Agent-only authentication through independently revocable credentials. */
export async function apiAuth(c: AuthContext, next: Next): Promise<Response | void> {
  const token = extractToken(c);
  if (!token) return c.text('Unauthorized', 401);
  const keyHash = await hashApiKey(token);
  if (!await resolveAgentAuth(c, keyHash)) return c.text('Unauthorized', 401);
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
  if (await resolveAgentAuth(c, keyHash)) return next();
  if (await resolveBossAuth(c, keyHash)) return next();
  return c.text('Unauthorized', 401);
}

/** Check if current context is boss-authenticated. */
export function isBossAuth(c: Context<{ Bindings: Env }>): boolean {
  return !!(c as AuthContext).bossId;
}

type AgentAuthRow = { id: string; key_id: AgentKeyId | null; last_used_at: string | null };
let warnedMissingAgentKeys = false;

async function findAgent(db: D1Database, keyHash: string): Promise<AgentAuthRow | null> {
  try {
    // A revoked row must block the legacy fallback. Keep this bridge for the deploy only.
    return await db.prepare(`SELECT a.id, k.id AS key_id, k.last_used_at FROM agent_keys k
      JOIN api_keys a ON a.id = k.agent_id WHERE k.key_hash = ? AND k.revoked_at IS NULL
      UNION ALL SELECT id, NULL AS key_id, NULL AS last_used_at FROM api_keys WHERE key_hash = ?
      AND NOT EXISTS (SELECT 1 FROM agent_keys WHERE key_hash = ?) LIMIT 1`)
      .bind(keyHash, keyHash, keyHash).first<AgentAuthRow>();
  } catch (error: unknown) {
    if (!(error instanceof Error) || !error.message.includes('no such table: agent_keys')) throw error;
    if (!warnedMissingAgentKeys) {
      warnedMissingAgentKeys = true;
      console.warn('agent_keys table unavailable; using legacy agent authentication until migration 0045');
    }
    return db.prepare('SELECT id, NULL AS key_id, NULL AS last_used_at FROM api_keys WHERE key_hash = ?')
      .bind(keyHash).first<AgentAuthRow>();
  }
}

async function resolveAgentAuth(c: AuthContext, keyHash: string): Promise<boolean> {
  const agent = await findAgent(c.env.DB, keyHash);
  if (!agent) return false;
  c.agentId = agent.id;
  c.agentKeyId = agent.key_id;
  c.executionCtx.waitUntil(c.env.DB.prepare("UPDATE api_keys SET last_used_at = datetime('now') WHERE id = ?")
    .bind(agent.id).run());
  const lastUsed = agent.last_used_at ? Date.parse(agent.last_used_at.replace(' ', 'T') + 'Z') : 0;
  if (agent.key_id && Date.now() - lastUsed >= 60_000) {
    c.executionCtx.waitUntil(c.env.DB.prepare(`UPDATE agent_keys SET last_used_at = datetime('now')
      WHERE id = ? AND revoked_at IS NULL
      AND (last_used_at IS NULL OR last_used_at <= datetime('now', '-1 minute'))`)
      .bind(agent.key_id).run());
  }
  return true;
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
