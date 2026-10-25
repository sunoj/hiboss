// Defines decision shape and definitive closure conditions shared with pending inputs.
// Exports SQL predicates, isDecisionAnswerable for the boss reply route and isDecisionReply.
// Depends on D1 message rows and the shared open-status predicate; age is display-only.

import type { Env } from './types';
import { OPEN_MESSAGE_STATUS } from './message-status';

export const DECISION_MESSAGE_SQL = `messages.direction = 'agent_to_boss'
  AND (CASE WHEN json_valid(messages.metadata)
       THEN json_array_length(messages.metadata, '$.options') > 0
       ELSE 0 END
       OR messages.mode = 'blocking')`;

export const OPEN_DECISION_SQL = `${OPEN_MESSAGE_STATUS.replace('status', 'messages.status')}
  AND (messages.expires_at IS NULL OR messages.expires_at > ?)
  AND (CASE WHEN json_valid(messages.metadata)
       THEN json_extract(messages.metadata, '$.options_expired') IS NOT 1
       ELSE 1 END)`;

type ReplyParty = { direction: string; agent_id: string; session_id?: string | null };

/**
 * Whether `reply` answers `parent`: a boss_to_agent row answers a boss ask; an agent_to_agent row
 * answers a peer ask when another agent wrote it, or the same agent from a named session other than
 * the ask's. Only such a reply closes an ask; any other reply is stored and leaves it open.
 */
export function isDecisionReply(parent: ReplyParty, reply: ReplyParty): boolean {
  if (parent.direction === 'agent_to_agent') {
    const session = reply.session_id ?? null;
    return reply.direction === 'agent_to_agent' && (reply.agent_id !== parent.agent_id
      || (session !== null && session !== (parent.session_id ?? null)));
  }
  if (parent.direction === 'agent_to_boss') return reply.direction === 'boss_to_agent';
  return true;
}

/** Non-decision messages remain replyable regardless of status, deadline, or metadata. */
export async function isDecisionAnswerable(env: Env, parentId: string): Promise<boolean> {
  const row = await env.DB.prepare(
    `SELECT CASE WHEN ${DECISION_MESSAGE_SQL} THEN (${OPEN_DECISION_SQL}) ELSE 1 END AS answerable
     FROM messages WHERE messages.id = ?`,
  ).bind(new Date().toISOString(), parentId).first<{ answerable: number }>();
  return row?.answerable === 1;
}
