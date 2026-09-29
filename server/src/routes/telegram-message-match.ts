// Resolves Telegram message identity within the chat that received it.
// Exports reply/reaction and pending-message lookups for webhook handlers.
// Depends on recorded delivery destinations and legacy agent channel configs.

import type { Env } from '../types';

const legacyChatMatch = `json_extract(m.metadata, '$.telegram_chat_id') IS NULL
  AND NOT EXISTS (SELECT 1 FROM message_deliveries md WHERE md.message_id = m.id
    AND (md.status IN ('sent', 'delivered') OR md.external_message_id IS NOT NULL))
  AND EXISTS (SELECT 1 FROM channel_configs cc WHERE cc.agent_id = m.agent_id
    AND cc.channel = 'telegram' AND cc.enabled = 1
    AND CAST(json_extract(cc.config, '$.chat_id') AS TEXT) = ?)`;

export async function findTelegramMessageInChat(
  env: Env, agentId: string, chatId: string, externalId: number,
): Promise<{ id: string; metadata: string | null } | null> {
  return env.DB.prepare(`SELECT m.id, m.metadata FROM messages m
    WHERE m.agent_id = ? AND m.channel = 'telegram'
      AND ((json_extract(m.metadata, '$.telegram_message_id') = ?
        AND (CAST(json_extract(m.metadata, '$.telegram_chat_id') AS TEXT) = ?
          OR (${legacyChatMatch})))
        OR EXISTS (SELECT 1 FROM message_deliveries md
          JOIN boss_destinations d ON d.id = md.destination_id
          WHERE md.message_id = m.id AND md.external_message_id = CAST(? AS TEXT)
            AND d.kind = 'telegram_chat'
            AND CAST(json_extract(d.target, '$.chat_id') AS TEXT) = ?))
    LIMIT 1`)
    .bind(agentId, externalId, chatId, chatId, externalId, chatId)
    .first<{ id: string; metadata: string | null }>();
}

export async function findPendingTelegramMessageInChat(
  env: Env, agentId: string, chatId: string,
): Promise<string | null> {
  const pending = await env.DB.prepare(`SELECT m.id FROM messages m
    WHERE m.agent_id = ? AND m.direction = 'agent_to_boss'
      AND m.mode = 'blocking' AND m.channel = 'telegram'
      AND m.status IN ('sent', 'delivered')
      AND (CAST(json_extract(m.metadata, '$.telegram_chat_id') AS TEXT) = ?
        OR EXISTS (SELECT 1 FROM message_deliveries md
          JOIN boss_destinations d ON d.id = md.destination_id
          WHERE md.message_id = m.id AND md.status IN ('sent', 'delivered')
            AND d.kind = 'telegram_chat'
            AND CAST(json_extract(d.target, '$.chat_id') AS TEXT) = ?)
        OR (${legacyChatMatch}))
    ORDER BY m.created_at DESC LIMIT 1`)
    .bind(agentId, chatId, chatId, chatId)
    .first<{ id: string }>();
  return pending?.id ?? null;
}
