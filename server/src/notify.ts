// Best-effort webhook notification to agent callback URLs.
// Exports notifyAgentCallback which POSTs new messages to registered URLs.
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
