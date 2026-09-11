// Deterministic destination-first routing of external chats and threads to agents.
// Exports inbound lookup; depends on D1 route/provider storage, with no legacy reads.
import type { Env } from '../types';
import { jsonObject } from './types';

export interface InboundRoute {
  agent_id: string;
  config: string;
  session_id: string | null;
  inbound: true;
}

export async function findInboundRoute(env: Env, channel: 'telegram' | 'discord', externalId: string,
  body?: string, threadId?: string): Promise<InboundRoute | null> {
  const rows = await env.DB.prepare(`SELECT i.target_agent_id, i.pattern, d.target, p.credentials,
    r.session_id, r.external_thread_id FROM inbound_routes i
    JOIN boss_destinations d ON d.id = i.destination_id JOIN bosses b ON b.id = d.boss_id
    JOIN channel_providers p ON p.id = d.provider_id
    LEFT JOIN destination_routes r ON r.destination_id = d.id
      AND r.external_thread_id = COALESCE(?, ?)
    WHERE d.enabled = 1 AND p.provider = ?
    AND (CAST(COALESCE(json_extract(d.target, '$.chat_id'), json_extract(d.target, '$.channel_id')) AS TEXT) = ?
      OR (? = 'discord' AND r.external_thread_id = ?))
    AND (b.role = 'admin' OR EXISTS (SELECT 1 FROM boss_agent_access a WHERE a.boss_id = b.id AND a.agent_id = i.target_agent_id))
    ORDER BY i.priority DESC, i.id, r.id`)
    .bind(threadId ?? null, externalId, channel, externalId, channel, externalId)
    .all<{ target_agent_id: string; pattern: string | null; target: string; credentials: string; session_id: string | null; external_thread_id: string | null }>();
  for (const row of rows.results) {
    if (row.pattern !== null) {
      if (body === undefined) continue;
      try { if (!new RegExp(row.pattern).test(body)) continue; } catch { continue; }
    }
    const session = row.session_id ? await env.DB.prepare('SELECT id FROM sessions WHERE id = ? AND agent_id = ?')
      .bind(row.session_id, row.target_agent_id).first<{ id: string }>() : null;
    const config = { ...jsonObject(row.target), ...jsonObject(row.credentials) };
    if (channel === 'telegram' && row.external_thread_id) config.message_thread_id = Number(row.external_thread_id);
    return { agent_id: row.target_agent_id, config: JSON.stringify(config), session_id: session?.id ?? null, inbound: true };
  }
  return null;
}
