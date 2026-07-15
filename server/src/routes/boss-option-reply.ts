// Claims an option message so concurrent Boss clients have exactly one winner.
// Exports: claimOptionReply and its explicit result union.
// Depends on D1, MessageRow metadata, and server time.

import type { Env, MessageRow } from '../types';

export type OptionClaimResult =
  | { kind: 'not_option' }
  | { kind: 'invalid_choice' }
  | { kind: 'claimed' }
  | { kind: 'resolved' };

type OptionReplyParent = Pick<MessageRow, 'id' | 'metadata'>;

export async function claimOptionReply(
  env: Env,
  parent: OptionReplyParent,
  choice: string,
): Promise<OptionClaimResult> {
  const options = parseOptions(parent.metadata);
  if (!options) return { kind: 'not_option' };
  if (!options.includes(choice)) return { kind: 'invalid_choice' };

  const now = new Date().toISOString();
  const claimed = await env.DB.prepare(
    `UPDATE messages
     SET status = 'replied', updated_at = datetime('now')
     WHERE id = ?
       AND status IN ('sent', 'delivered', 'read')
       AND expires_at > ?
     RETURNING id`,
  ).bind(parent.id, now).first<{ id: string }>();
  return claimed ? { kind: 'claimed' } : { kind: 'resolved' };
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
