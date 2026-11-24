// Interprets decision metadata shared by Today, Messages and Sessions.
// The server's required-input stream determines open membership.

import type { MessageResponse } from '$lib/api/types';
import { extractOptions } from '$lib/api/mappers';

export function isDecision(message: MessageResponse): boolean {
	return message.direction === 'agent_to_boss' && (message.mode === 'blocking'
		|| extractOptions(message.metadata).length > 0);
}

export function deadlineOf(message: MessageResponse): string | null {
	return message.metadata?.ask_deadline === true || typeof message.metadata?.default_option === 'string'
		? message.expires_at ?? null : null;
}

export function compareDecisions(a: MessageResponse, b: MessageResponse): number {
	const aDue = Date.parse(deadlineOf(a) ?? '') || Infinity;
	const bDue = Date.parse(deadlineOf(b) ?? '') || Infinity;
	const priority = ['critical', 'high', 'normal', 'low'];
	return (aDue === bDue ? 0 : aDue < bDue ? -1 : 1)
		|| priority.indexOf(a.priority) - priority.indexOf(b.priority)
		|| Date.parse(b.created_at) - Date.parse(a.created_at);
}
