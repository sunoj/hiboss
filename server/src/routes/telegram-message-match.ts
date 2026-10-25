// Resolves Telegram message identity within the chat that received it.
// Exports reply/reaction and pending-message lookups for webhook handlers.
// Depends on recorded delivery destinations, legacy agent channel configs and boss access.

import type { Env, MessageRow } from '../types';
import { hasBossAccess } from './webhook-helpers';

const legacyChatMatch = `json_extract(m.metadata, '$.telegram_chat_id') IS NULL
  AND NOT EXISTS (SELECT 1 FROM message_deliveries md WHERE md.message_id = m.id
    AND (md.status IN ('sent', 'delivered') OR md.external_message_id IS NOT NULL))
  AND EXISTS (SELECT 1 FROM channel_configs cc WHERE cc.agent_id = m.agent_id
    AND cc.channel = 'telegram' AND cc.enabled = 1
    AND CAST(json_extract(cc.config, '$.chat_id') AS TEXT) = ?)`;

/** The HiBoss message delivered to this chat as Telegram message `externalId`, whatever its agent. */
export async function findTelegramMessageInChat(
  env: Env, chatId: string, externalId: number,
): Promise<MessageRow | null> {
  // Destination sends store no message channel; only channel-path sends carry 'telegram'.
  return env.DB.prepare(`SELECT m.* FROM messages m
    WHERE (m.channel = 'telegram' AND json_extract(m.metadata, '$.telegram_message_id') = ?
        AND (CAST(json_extract(m.metadata, '$.telegram_chat_id') AS TEXT) = ?
          OR (${legacyChatMatch})))
      OR EXISTS (SELECT 1 FROM message_deliveries md
        JOIN boss_destinations d ON d.id = md.destination_id
        WHERE md.message_id = m.id AND md.external_message_id = ?
          AND d.kind = 'telegram_chat'
          AND CAST(json_extract(d.target, '$.chat_id') AS TEXT) = ?)
    ORDER BY m.created_at DESC LIMIT 1`)
    // D1 binds a JS number as REAL, so CAST(? AS TEXT) would give '77.0'; bind the stored text.
    .bind(externalId, chatId, chatId, String(externalId), chatId)
    .first<MessageRow>();
}

/**
 * The message a Telegram text replies to, when it was delivered to this chat and the replying
 * boss may access its agent. Null when there is no reply, no match, or no access.
 */
export async function findRepliedTelegramMessage(
  env: Env, chatId: string, message: Record<string, unknown> | undefined,
  boss: { id: string; role: string } | null,
): Promise<MessageRow | null> {
  const replyId = (message?.['reply_to_message'] as Record<string, unknown> | undefined)?.['message_id'];
  if (typeof replyId !== 'number') return null;
  const parent = await findTelegramMessageInChat(env, chatId, replyId);
  if (!parent || (boss && !(await hasBossAccess(env, boss.id, parent.agent_id, boss.role)))) return null;
  return parent;
}

export async function findPendingTelegramMessageInChat(
  env: Env, agentId: string, chatId: string,
): Promise<string | null> {
  const pending = await env.DB.prepare(`SELECT m.id FROM messages m
    WHERE m.agent_id = ? AND m.direction = 'agent_to_boss'
      AND m.mode = 'blocking' AND m.status IN ('sent', 'delivered')
      AND ((m.channel = 'telegram' AND (CAST(json_extract(m.metadata, '$.telegram_chat_id') AS TEXT) = ?
          OR (${legacyChatMatch})))
        OR EXISTS (SELECT 1 FROM message_deliveries md
          JOIN boss_destinations d ON d.id = md.destination_id
          WHERE md.message_id = m.id AND md.status IN ('sent', 'delivered')
            AND d.kind = 'telegram_chat'
            AND CAST(json_extract(d.target, '$.chat_id') AS TEXT) = ?))
    ORDER BY m.created_at DESC LIMIT 1`)
    .bind(agentId, chatId, chatId, chatId)
    .first<{ id: string }>();
  return pending?.id ?? null;
}
