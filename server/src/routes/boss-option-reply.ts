// Inserts one answer to an open ask, then marks that ask replied in one D1 batch.
// Exports: persistOptionReply and its explicit result union.
// Depends on D1, session events, MessageRow metadata, server time and the resolution fan-out.

import type { Env, MessageRow } from '../types';
import { insertMessageWithEvent, messageEventStatement } from '../session-events';
import { OPEN_MESSAGE_STATUS } from '../message-status';
import { announceResolution, type Announce } from '../push/resolution';

export type OptionClaimResult =
  | { kind: 'not_option'; reply: MessageRow }
  | { kind: 'invalid_choice' }
  | { kind: 'claimed'; reply: MessageRow }
  | { kind: 'failed' }
  | { kind: 'resolved' };

type OptionReplyParent = Pick<MessageRow,
  'id' | 'agent_id' | 'metadata' | 'direction' | 'mode' | 'priority' | 'created_at'>;

/**
 * `allowExpired` admits an ask past its deadline (the timeout default). `announce` receives the
 * committed resolution: request routes pass deferredAnnounce, the cron sweep its collector.
 */
export interface ClaimOptions { allowExpired?: boolean; announce?: Announce }

/**
 * Persists an ask answer only if its conditional insert wins.
 *
 * `allowFreeText` must be false for channel callbacks: Telegram callback_data is
 * client-supplied and both callback paths admit viewer-role bosses, so binding the
 * reply to an offered option is what stops a viewer from turning a button press into
 * an arbitrary agent instruction. Only the boss API — which rejects viewers outright —
 * passes true.
 */
export async function persistOptionReply(
  env: Env,
  parent: OptionReplyParent,
  choice: string,
  allowFreeText: boolean,
  insertSql: string,
  insertBinds: readonly unknown[],
  sessionId: string | null,
  { allowExpired = false, announce = announceResolution }: ClaimOptions = {},
): Promise<OptionClaimResult> {
  const options = parseOptions(parent.metadata);
  if (options && !allowFreeText && !options.includes(choice)) return { kind: 'invalid_choice' };
  const isAsk = parent.direction === 'agent_to_boss' && (parent.mode === 'blocking' || options !== null);
  if (!isAsk) {
    const reply = await insertMessageWithEvent(env, insertSql, insertBinds, sessionId);
    return reply ? { kind: 'not_option', reply } : { kind: 'failed' };
  }
  const now = new Date().toISOString();
  if (!insertSql.includes('VALUES (') || !insertSql.includes('RETURNING *')) {
    throw new Error('reply insert must use VALUES and RETURNING');
  }
  const openAsk = `parent.id = ? AND ${OPEN_MESSAGE_STATUS.replace('status', 'parent.status')}
    AND (? = 1 OR parent.expires_at IS NULL OR parent.expires_at > ?)
    AND NOT EXISTS (SELECT 1 FROM messages answer WHERE answer.reply_to = parent.id
      AND answer.direction = 'boss_to_agent')`;
  const conditionalInsert = insertSql.replace('VALUES (', 'SELECT ').replace(
    /\) (ON CONFLICT|RETURNING \*)/, ` FROM messages parent WHERE ${openAsk} $1`,
  );
  const statements = [
    env.DB.prepare(conditionalInsert).bind(...insertBinds, parent.id, allowExpired ? 1 : 0, now),
    env.DB.prepare(`UPDATE messages SET status = 'replied', updated_at = datetime('now')
      WHERE id = ? AND EXISTS (SELECT 1 FROM messages WHERE id = ?)`).bind(parent.id, String(insertBinds[0])),
  ];
  if (sessionId) statements.push(messageEventStatement(env, sessionId, String(insertBinds[0])));
  const results = await env.DB.batch(statements);
  const reply = results[0]?.results[0] as MessageRow | undefined;
  if (reply) {
    // Every path that answers an ask claims it here, after the batch committed.
    await announce(env, parent, 'replied');
    return { kind: 'claimed', reply };
  }
  const stillOpen = await env.DB.prepare(`SELECT 1 AS open FROM messages parent WHERE ${openAsk}`)
    .bind(parent.id, allowExpired ? 1 : 0, now).first<{ open: number }>();
  return stillOpen ? { kind: 'failed' } : { kind: 'resolved' };
}

function parseOptions(metadata: string | null): string[] | null {
  if (!metadata) return null;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    const options = parsed['options'];
    if (!Array.isArray(options) || !options.every((item) => typeof item === 'string')) {
      return 'options' in parsed ? [] : null;
    }
    return options;
  } catch {
    return null;
  }
}

/** Saves channel text as a standalone message if its candidate ask has closed. */
export async function persistChannelText(
  env: Env,
  parent: OptionReplyParent | null,
  body: string,
  insertSql: string,
  insertBinds: readonly unknown[],
  sessionId: string | null,
  announce?: Announce,
): Promise<MessageRow | null> {
  if (!parent) return insertMessageWithEvent(env, insertSql, insertBinds, sessionId);
  const result = await persistOptionReply(env, parent, body, true, insertSql, insertBinds, sessionId, { announce });
  if (result.kind === 'claimed' || result.kind === 'not_option') return result.reply;
  if (result.kind !== 'resolved') return null;
  // Each channel insert statement binds reply_to at index 8.
  const unlinked = [...insertBinds];
  unlinked[8] = null;
  return insertMessageWithEvent(env, insertSql, unlinked, sessionId);
}
