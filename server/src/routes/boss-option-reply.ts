// Claims an option message so concurrent Boss clients have exactly one winner.
// Exports: persistOptionReply and its explicit result union.
// Depends on D1, session events, MessageRow metadata, and server time.

import type { Env, MessageRow } from '../types';
import { insertMessageWithEvent, messageEventStatement } from '../session-events';
import { OPEN_MESSAGE_STATUS } from '../message-status';

export type OptionClaimResult =
  | { kind: 'not_option'; reply: MessageRow }
  | { kind: 'invalid_choice' }
  | { kind: 'claimed'; reply: MessageRow }
  | { kind: 'failed' }
  | { kind: 'resolved' };

type OptionReplyParent = Pick<MessageRow, 'id' | 'metadata' | 'status'>;

/**
 * Persists a reply only if its option claim wins.
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
  allowExpired = false,
): Promise<OptionClaimResult> {
  const options = parseOptions(parent.metadata);
  if (!options) {
    const reply = await insertMessageWithEvent(env, insertSql, insertBinds, sessionId);
    return reply ? { kind: 'not_option', reply } : { kind: 'failed' };
  }
  if (!allowFreeText && !options.includes(choice)) return { kind: 'invalid_choice' };

  const now = new Date().toISOString();
  const claim = env.DB.prepare(
    `UPDATE messages
     SET status = 'replied', updated_at = datetime('now')
     WHERE id = ?
       AND ${OPEN_MESSAGE_STATUS}
       AND (? = 1 OR expires_at IS NULL OR expires_at > ?)
     RETURNING id`,
  ).bind(parent.id, allowExpired ? 1 : 0, now);
  // D1 batch executes these statements in one transaction. changes() ties the
  // insert to this claim, and the event SELECT sees only a persisted reply.
  if (!insertSql.includes('VALUES (') || !insertSql.includes(') RETURNING *')) {
    throw new Error('reply insert must use VALUES and RETURNING');
  }
  const conditionalInsert = insertSql.replace('VALUES (', 'SELECT ').replace(') RETURNING *', ' WHERE changes() = 1 RETURNING *');
  const statements = [
    env.DB.prepare('SELECT status FROM messages WHERE id = ?').bind(parent.id),
    claim,
    env.DB.prepare(conditionalInsert).bind(...insertBinds),
  ];
  if (sessionId) statements.push(messageEventStatement(env, sessionId, String(insertBinds[0])));
  const results = await env.DB.batch(statements);
  if (!results[1]?.results.length) return { kind: 'resolved' };
  const reply = results[2]?.results[0] as MessageRow | undefined;
  if (reply) return { kind: 'claimed', reply };
  const previous = results[0]?.results[0] as { status: MessageRow['status'] } | undefined;
  if (!previous) throw new Error('claimed option has no previous status');
  // A trigger may silently ignore the insert; restore the prior status then.
  await env.DB.prepare("UPDATE messages SET status = ?, updated_at = datetime('now') WHERE id = ? AND status = 'replied' AND NOT EXISTS (SELECT 1 FROM messages WHERE id = ?)")
    .bind(previous.status, parent.id, String(insertBinds[0])).run();
  return { kind: 'failed' };
}

function parseOptions(metadata: string | null): string[] | null {
  if (!metadata) return null;
  try {
    const parsed = JSON.parse(metadata) as Record<string, unknown>;
    const options = parsed['options'];
    if (!Array.isArray(options) || !options.every((item) => typeof item === 'string')) {
      return null;
    }
    return options;
  } catch {
    return null;
  }
}
