// Shared helpers for webhook route handlers: boss auth, routing rules, utils.
// Exports boss lookup, routing evaluation, and message mapping helpers.
// Depends on Env typings and D1 bindings.

import type { Env, MessageResponse, MessageRow } from '../types';

export function asString(value: unknown): string | undefined {
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return value.toString();
  return undefined;
}

export function mapMessage(row: MessageRow): MessageResponse {
  return { ...row, metadata: safeJson(row.metadata) };
}

function safeJson(value: string | null): Record<string, unknown> | null {
  if (!value) return null;
  try {
    return JSON.parse(value) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export async function evaluateRoutingRules(env: Env, channel: string, body: string, defaultAgentId: string): Promise<string | null> {
  const rules = await env.DB
    .prepare('SELECT target_agent_id, pattern FROM routing_rules WHERE channel = ? AND enabled = 1 ORDER BY priority DESC')
    .bind(channel)
    .all<{ target_agent_id: string; pattern: string }>();
  for (const rule of rules.results ?? []) {
    try {
      if (new RegExp(rule.pattern).test(body)) {
        return rule.target_agent_id !== defaultAgentId ? rule.target_agent_id : null;
      }
    } catch { /* skip invalid regex */ }
  }
  return null;
}

type BossLookupError = 'unknown sender' | 'viewer cannot send messages';

export async function resolveBossForChannel(
  env: Env,
  channel: 'telegram' | 'discord',
  userId: string | undefined,
  allowViewer: boolean
): Promise<{ boss: { id: string; name: string; role: string } | null; error?: BossLookupError }> {
  if ((await countBosses(env)) === 0) return { boss: null };
  if (!userId) return { boss: null, error: 'unknown sender' };
  const boss = await identifyBoss(env, channel, userId);
  if (!boss) return { boss: null, error: 'unknown sender' };
  if (!allowViewer && boss.role === 'viewer') return { boss: null, error: 'viewer cannot send messages' };
  return { boss };
}

async function identifyBoss(
  env: Env,
  channel: 'telegram' | 'discord',
  userId: string
): Promise<{ id: string; name: string; role: string } | null> {
  const col = channel === 'telegram' ? 'telegram_user_id' : 'discord_user_id';
  const row = await env.DB
    .prepare(`SELECT id, name, role FROM bosses WHERE ${col} = ? LIMIT 1`)
    .bind(userId)
    .first<{ id: string; name: string; role: string }>();
  return row ?? null;
}

export async function hasBossAccess(env: Env, bossId: string, agentId: string, bossRole: string): Promise<boolean> {
  if (bossRole === 'admin') return true;
  const row = await env.DB
    .prepare('SELECT 1 AS present FROM boss_agent_access WHERE boss_id = ? AND agent_id = ? LIMIT 1')
    .bind(bossId, agentId)
    .first<{ present: number }>();
  return !!row;
}

async function countBosses(env: Env): Promise<number> {
  const row = await env.DB
    .prepare('SELECT COUNT(*) AS total FROM bosses')
    .first<{ total: number }>();
  return row?.total ?? 0;
}
