// Metadata lookups shared by message delivery paths.
// Exports raw display lookups; depends only on the D1 binding.

import type { Env } from '../types';

export async function fetchAgentName(env: Env, agentId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT name FROM api_keys WHERE id = ?')
    .bind(agentId)
    .first<{ name: string }>();
  return row?.name ?? null;
}

export async function fetchSessionLabel(env: Env, sessionId: string | null): Promise<string | null> {
  if (!sessionId) return null;
  const row = await env.DB
    .prepare('SELECT label FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ label: string | null }>();
  return row?.label ?? null;
}
