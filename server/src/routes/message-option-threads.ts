// Creates and remembers Discord threads used to deliver option messages.
// Exports ensureThreadForSession for message routing.
// Depends on D1 session records and the Discord channel adapter.

import type { Channel, Env } from '../types';
import { createDiscordThread, addDiscordThreadMember } from '../channels/discord';
import { fetchAgentName } from './message-queries';

/** Auto-create a Discord thread for this session if use_threads is enabled. */
export async function ensureThreadForSession(
  env: Env,
  agentId: string,
  sessionId: string | null,
  channelConfig: { channel: Channel; config: Record<string, unknown> },
  discordMessageId: string | undefined,
  messageBody?: string,
): Promise<string | undefined> {
  if (channelConfig.channel !== 'discord') return undefined;
  const cfg = channelConfig.config;
  if (!cfg['use_threads']) return undefined;
  if (!sessionId) return undefined;

  const session = await env.DB
    .prepare('SELECT discord_thread_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ discord_thread_id: string | null }>();
  if (session?.discord_thread_id) return session.discord_thread_id;
  if (!discordMessageId) return undefined;

  const botToken = cfg['bot_token'] as string | undefined;
  const channelId = cfg['channel_id'] as string | undefined;
  if (!botToken || !channelId) return undefined;

  const sessionRow = await env.DB
    .prepare('SELECT label, branch FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ label: string | null; branch: string | null }>();
  // Thread title: "repo/branch: first message summary" (max 100 chars on Discord).
  const prefix = sessionRow?.label ?? sessionRow?.branch;
  const summary = messageBody ? messageBody.split('\n')[0].slice(0, 60) : undefined;
  const threadName = prefix && summary
    ? `${prefix}: ${summary}`.slice(0, 100)
    : prefix ?? summary ?? `${await fetchAgentName(env, agentId) ?? 'agent'}-session`;

  try {
    const threadId = await createDiscordThread(botToken, channelId, discordMessageId, threadName);
    await env.DB
      .prepare('UPDATE sessions SET discord_thread_id = ? WHERE id = ?')
      .bind(threadId, sessionId)
      .run();
    // Bot-created threads do not automatically include the bosses.
    const bosses = await env.DB
      .prepare('SELECT b.discord_user_id FROM bosses b JOIN boss_agent_access ba ON ba.boss_id = b.id WHERE ba.agent_id = ? AND b.discord_user_id IS NOT NULL')
      .bind(agentId)
      .all<{ discord_user_id: string }>();
    for (const boss of bosses.results ?? []) {
      await addDiscordThreadMember(botToken, threadId, boss.discord_user_id).catch(() => {});
    }
    return threadId;
  } catch {
    return undefined;
  }
}
