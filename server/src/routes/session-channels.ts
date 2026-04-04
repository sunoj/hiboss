// Session channel helpers for per-session Telegram topic routing.
// Exports topic lookup and creation helpers used by delivery and webhooks.
// Depends on D1 session rows and the Telegram forum topic adapter.

import { createForumTopic } from '../channels/telegram';
import type { Env, TelegramChannelConfig } from '../types';

const TELEGRAM_TOPIC_NAME_LIMIT = 128;
const SESSION_ID_PREFIX_LENGTH = 8;

export async function fetchTelegramTopicIdForSession(
  env: Env,
  sessionId: string | null | undefined,
): Promise<number | undefined> {
  if (!sessionId) return undefined;
  const session = await env.DB
    .prepare('SELECT telegram_topic_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ telegram_topic_id: number | null }>();
  return session?.telegram_topic_id ?? undefined;
}

export async function ensureTopicForSession(
  env: Env,
  sessionId: string,
  agentName: string,
  sessionLabel: string | null,
  tgConfig: TelegramChannelConfig,
): Promise<number | undefined> {
  const session = await env.DB
    .prepare('SELECT telegram_topic_id FROM sessions WHERE id = ?')
    .bind(sessionId)
    .first<{ telegram_topic_id: number | null }>();
  if (!session) return tgConfig.message_thread_id;
  if (session.telegram_topic_id) return session.telegram_topic_id;
  if (tgConfig.use_topics !== true) return tgConfig.message_thread_id;

  try {
    const topicId = await createForumTopic(
      tgConfig.bot_token,
      tgConfig.chat_id,
      buildTelegramTopicName(agentName, sessionId, sessionLabel),
    );
    await env.DB
      .prepare('UPDATE sessions SET telegram_topic_id = ? WHERE id = ?')
      .bind(topicId, sessionId)
      .run();
    return topicId;
  } catch {
    return tgConfig.message_thread_id;
  }
}

export async function findTelegramSessionRoute(
  env: Env,
  chatId: string,
  topicId: number,
): Promise<{ agent_id: string; config: string; session_id: string } | null> {
  const route = await env.DB
    .prepare(
      `SELECT cc.agent_id, cc.config, s.id AS session_id
       FROM sessions s
       JOIN channel_configs cc
         ON cc.agent_id = s.agent_id
       WHERE cc.channel = 'telegram'
         AND cc.enabled = 1
         AND json_extract(cc.config, '$.chat_id') = ?
         AND s.telegram_topic_id = ?
       LIMIT 1`
    )
    .bind(chatId, topicId)
    .first<{ agent_id: string; config: string; session_id: string }>();
  return route ?? null;
}

function buildTelegramTopicName(agentName: string, sessionId: string, sessionLabel: string | null): string {
  const trimmedLabel = sessionLabel?.trim();
  const fallbackName = `${agentName}/${sessionId.slice(0, SESSION_ID_PREFIX_LENGTH)}`;
  return (trimmedLabel || fallbackName).slice(0, TELEGRAM_TOPIC_NAME_LIMIT);
}
