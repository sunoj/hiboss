/**
 * Helper functions for message options and expiry.
 * Handles parsing options and expiring asks at their deadline.
 */

import { MESSAGE_METADATA_OBJECT_SQL } from './message-reactions';
import type { Env, MessageRow } from '../types';
import { replyTargetSession } from './message-helpers';
import { notifyAgentCallback } from '../notify';
import { createMessageId } from '../session-events';
import { systemMetadata } from '../message-security';
import { OPEN_MESSAGE_STATUS } from '../message-status';
import { persistOptionReply } from './boss-option-reply';
import { announceResolution, type Announce } from '../push/resolution';

const MAX_MESSAGE_OPTIONS = 5;
const OPTIONS_ERROR = 'options must be an array of 1 to 5 non-empty unique strings';
export { parseOptionMedia, type OptionMediaParseResult } from './option-media';

export type OptionsParseResult =
  | { ok: true; value: string[] | undefined }
  | { ok: false; error: string };

export function parseOptions(value: unknown): OptionsParseResult {
  if (value === undefined) return { ok: true, value: undefined };
  if (!Array.isArray(value) || value.length === 0 || value.length > MAX_MESSAGE_OPTIONS) {
    return { ok: false, error: OPTIONS_ERROR };
  }
  if (!value.every((option): option is string => typeof option === 'string')) {
    return { ok: false, error: OPTIONS_ERROR };
  }
  const options = value.map((option) => option.trim());
  if (options.some((option) => !option) || new Set(options).size !== options.length) {
    return { ok: false, error: OPTIONS_ERROR };
  }
  return { ok: true, value: options };
}

export async function expireMessageOptions(env: Env, agentId: string, message: MessageRow,
  announce: Announce = announceResolution): Promise<void> {
  // The timeout default answers only a boss ask; any other timed-out message just expires once.
  const meta = parseMetadata(message.metadata);
  const defaultOption = message.direction === 'agent_to_boss' ? getDefaultOption(meta) : null;
  if (defaultOption) {
    await autoResolveDefaultOption(env, agentId, message, defaultOption, announce);
    return;
  }
  await expireWithoutDefault(env, message, announce);
}

/** SET clause that expires an open ask without recording any choice. */
export const EXPIRE_ASK_SET_SQL = `status = 'expired', metadata = json_remove(json_set(
  ${MESSAGE_METADATA_OBJECT_SQL}, '$.options_expired', json('true')), '$.actions'),
  updated_at = datetime('now')`;

/**
 * Expires an open ask without answering it: nobody chose, so nothing is recorded as a
 * choice. Returns false when the ask was already resolved.
 */
export async function expireWithoutDefault(env: Env, message: MessageRow,
  announce: Announce = announceResolution): Promise<boolean> {
  const claimed = await env.DB
    .prepare(`UPDATE messages SET ${EXPIRE_ASK_SET_SQL} WHERE id = ? AND ${OPEN_MESSAGE_STATUS} RETURNING id`)
    .bind(message.id)
    .first<{ id: string }>();
  if (!claimed) return false;
  await announceExpiredAsk(env, message, announce);
  return true;
}

/** Resolution fan-out for an ask already expired without an answer. */
export async function announceExpiredAsk(env: Env, message: MessageRow,
  announce: Announce = announceResolution): Promise<void> {
  await announce(env, message, 'expired');
}

/** Unparseable metadata must not keep an ask open forever; expire it with a fresh object. */
function parseMetadata(raw: string | null): Record<string, unknown> {
  if (!raw) return {};
  try {
    const parsed: unknown = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function getDefaultOption(meta: Record<string, unknown>): string | null {
  const defaultOption = meta['default_option'];
  const options = meta['options'];
  if (typeof defaultOption !== 'string' || defaultOption.trim() === '') return null;
  if (!Array.isArray(options) || !options.every((option): option is string => typeof option === 'string')) {
    return null;
  }
  return options.includes(defaultOption) ? defaultOption : null;
}

async function autoResolveDefaultOption(
  env: Env,
  agentId: string,
  message: MessageRow,
  defaultOption: string,
  announce: Announce,
): Promise<void> {
  const outcome = await persistOptionReply(
    env,
    message,
    defaultOption,
    false,
    'INSERT INTO messages (id, agent_id, direction, mode, channel, body, status, priority, reply_to, metadata, target_session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *',
    [createMessageId(), agentId, 'boss_to_agent', 'async', 'api', defaultOption, 'sent', 'normal', message.id, JSON.stringify(systemMetadata({ auto_default: true })), replyTargetSession(message)],
    replyTargetSession(message),
    { allowExpired: true, announce },
  );
  if (outcome.kind !== 'claimed') return;
  const inserted = outcome.reply;
  await env.DB.prepare(`UPDATE messages SET metadata = json_remove(
    json_set(${MESSAGE_METADATA_OBJECT_SQL}, '$.options_expired', json('true')), '$.actions'),
    updated_at = datetime('now') WHERE id = ? AND status = 'replied'`)
    .bind(message.id).run();
  // Best-effort notifications: the default is already durably recorded above, so a failed
  // agent callback (e.g. unreachable URL) must not throw out of the cron path.
  try {
    await notifyAgentCallback(env, agentId, inserted);
    await withdrawResolvedOptions(env, message, defaultOption);
  } catch {
    // The resolution is already persisted.
  }
}

export async function withdrawResolvedOptions(env: Env, message: MessageRow, selectedOption: string): Promise<void> {
  await env.DB.prepare(`UPDATE messages SET metadata = json_remove(
    json_set(${MESSAGE_METADATA_OBJECT_SQL}, '$.options_resolved', json('true'),
      '$.selected_option', ?), '$.actions'), updated_at = datetime('now') WHERE id = ?`)
    .bind(selectedOption, message.id).run();
}
