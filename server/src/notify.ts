// Best-effort webhook notification to agent callback URLs.
// Exports notifyAgentCallback and notifyBossAgents for push delivery.
// Depends on D1 for callback lookup and global fetch for delivery.

import type { Env, MessageRow } from './types';

export async function notifyAgentCallback(env: Env, agentId: string, message: MessageRow): Promise<void> {
  try {
    const row = await env.DB
      .prepare('SELECT callback_url FROM api_keys WHERE id = ?')
      .bind(agentId)
      .first<{ callback_url: string | null }>();
    if (!row?.callback_url) {
      return;
    }
    await fetch(row.callback_url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    });
  } catch {
    // Best-effort: swallow errors to avoid disrupting the webhook response.
  }
}

/** Notify target agent via callback URL for agent-to-agent messages. */
export async function notifyTargetAgent(env: Env, targetAgentId: string, message: MessageRow): Promise<void> {
  await notifyAgentCallback(env, targetAgentId, message);
}

/** Notify boss-agents who have access to the given sub-agent. */
export async function notifyBossAgents(env: Env, subAgentId: string, message: MessageRow): Promise<void> {
  try {
    // Find boss-agents (bosses with agent_id set) who have access to this sub-agent
    const rows = await env.DB
      .prepare(
        `SELECT b.agent_id FROM bosses b
         WHERE b.agent_id IS NOT NULL AND (
           b.role = 'admin'
           OR b.id IN (SELECT boss_id FROM boss_agent_access WHERE agent_id = ?)
         )`
      )
      .bind(subAgentId)
      .all<{ agent_id: string }>();
    for (const row of rows.results ?? []) {
      await notifyAgentCallback(env, row.agent_id, message);
    }
  } catch {
    // Best-effort
  }
}
