// Metadata lookups and Discord thread configuration shared by message delivery paths.
// Exports raw display lookups and config resolution; depends only on the D1 binding.

import type { Env, MessageRow } from '../types';

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

export async function fetchDiscordThreadId(env: Env, sessionId: string): Promise<string | null> {
  const row = await env.DB
    .prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ discord_thread_id: string | null }>();
  return row?.discord_thread_id ?? null;
}

export async function resolveDiscordConfig(
  env: Env,
  message: MessageRow,
  config: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (!message.session_id || !config['use_threads']) return config;
  const threadId = await fetchDiscordThreadId(env, message.session_id);
  if (!threadId) return config;
  return { ...config, channel_id: threadId, thread_id: threadId };
}
