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

type ReplyParty = { direction: string; agent_id: string };

/**
 * Whether `reply` answers `parent`: a boss_to_agent row answers a boss ask; an agent_to_agent row
 * answers a peer ask only when a different agent wrote it. A row from the asking agent, from any of
 * its sessions, never answers. Only an answer closes an ask; other replies leave it open.
 */
export function isDecisionReply(parent: ReplyParty, reply: ReplyParty): boolean {
  if (parent.direction === 'agent_to_agent') {
    return reply.direction === 'agent_to_agent' && reply.agent_id !== parent.agent_id;
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
