/** Pure helpers for Messages module filtering and session grouping. */

import {
	coerceSessionStatus,
	type Direction,
	type MessageStatus,
	type Priority,
	type SessionStatus
} from '$lib/design/semantics';
import type { MessageResponse, MessagesQuery } from '$lib/api/types';

export type DirectionFilter = 'all' | Direction;
export type StatusFilter = 'all' | MessageStatus;
export type ViewMode = 'flat' | 'grouped';

export interface MessageFilterState {
	direction: DirectionFilter;
	priorities: Priority[];
	status: StatusFilter;
	agent: string;
	search: string;
	session: string;
}

export interface SessionGroup {
	key: string;
	title: string;
	status: SessionStatus;
	messages: MessageResponse[];
	latestAt: string;
}

export const DEFAULT_FILTERS: MessageFilterState = {
	direction: 'all',
	priorities: [],
	status: 'all',
	agent: '',
	search: '',
	session: ''
};

export const PAGE_SIZE = 50;

export function hasMorePages(loadedCount: number, total: number): boolean {
	return loadedCount < total;
}

/** Map UI filters to boss API query params the client supports. */
export function buildMessagesQuery(
	filters: MessageFilterState,
	opts: { limit?: number; offset?: number } = {}
): MessagesQuery {
	const query: MessagesQuery = {
		limit: opts.limit ?? 50,
		offset: opts.offset ?? 0
	};

	// Server: direction=all → all dirs; anything else → agent_to_boss only.
	// Non-inbox directions need direction=all + client-side filter.
	if (filters.direction === 'all' || filters.direction === 'boss_to_agent' || filters.direction === 'agent_to_agent') {
		query.direction = 'all';
	} else {
		query.direction = 'agent_to_boss';
	}

	if (filters.priorities.length > 0) {
		query.priority = filters.priorities.join(',');
	}
	const agent = filters.agent.trim();
	if (agent) query.agent = agent;
	const search = filters.search.trim();
	if (search) query.search = search;
	const session = filters.session.trim();
	if (session) query.session = session;

	return query;
}

/** Client-side filters for fields the list API does not support (status, extra directions). */
export function applyLocalFilters(
	messages: MessageResponse[],
	filters: MessageFilterState
): MessageResponse[] {
	return messages.filter((m) => {
		if (filters.direction !== 'all' && m.direction !== filters.direction) return false;
		if (filters.status !== 'all' && m.status !== filters.status) return false;
		return true;
	});
}

export function sessionTitle(message: MessageResponse): string {
	const label = message.session_label?.trim();
	if (label) return label;
	const branch = message.session_branch?.trim();
	if (branch) return branch;
	const id = message.session_id?.trim();
	if (id) return shortId(id);
	return 'No session';
}

export function shortId(id: string, len = 8): string {
	return id.length <= len ? id : id.slice(0, len);
}

/** Group messages by session; sections ordered by most-recent activity. */
export function groupBySession(messages: MessageResponse[]): SessionGroup[] {
	const map = new Map<string, SessionGroup>();

	for (const message of messages) {
		const key = message.session_id?.trim() || '__none__';
		const existing = map.get(key);
		if (!existing) {
			map.set(key, {
				key,
				title: sessionTitle(message),
				status: coerceSessionStatus(message.session_status),
				messages: [message],
				latestAt: message.created_at
			});
			continue;
		}
		existing.messages.push(message);
		if (Date.parse(message.created_at) > Date.parse(existing.latestAt)) {
			existing.latestAt = message.created_at;
			existing.title = sessionTitle(message);
			existing.status = coerceSessionStatus(message.session_status);
		}
	}

	return [...map.values()].sort(
		(a, b) => Date.parse(b.latestAt) - Date.parse(a.latestAt)
	);
}

export function togglePriority(current: Priority[], priority: Priority): Priority[] {
	return current.includes(priority)
		? current.filter((p) => p !== priority)
		: [...current, priority];
}

export function formatAbsoluteTime(iso: string): string {
	const ms = Date.parse(iso);
	if (Number.isNaN(ms)) return '—';
	return new Date(ms).toLocaleString(undefined, {
		year: 'numeric',
		month: 'short',
		day: 'numeric',
		hour: '2-digit',
		minute: '2-digit',
		second: '2-digit'
	});
}
