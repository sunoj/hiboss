// Merges paginated transcript data and associates decision replies across page boundaries.
// Depends on the message contract and shared decision classification.

import type { MessageResponse } from '$lib/api/types';
import { isDecision } from '$lib/decisions/decision';

export function mergeTranscript(
	existing: MessageResponse[], incoming: MessageResponse[]
): MessageResponse[] {
	const unique = new Map(existing.map((message) => [message.id, message]));
	for (const message of incoming) unique.set(message.id, message);
	return [...unique.values()].sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at));
}

export function linkDecisionReplies(messages: MessageResponse[]): MessageResponse[] {
	const replies = new Map<string, MessageResponse[]>();
	for (const message of messages) {
		if (!message.reply_to) continue;
		const thread = replies.get(message.reply_to) ?? [];
		thread.push(message);
		replies.set(message.reply_to, thread);
	}
	return messages.map((message) => {
		if (!isDecision(message)) return message;
		const children = replies.get(message.id) ?? [];
		return { ...message, replies: mergeTranscript(message.replies ?? [], children) };
	});
}
