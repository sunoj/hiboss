/** Pure helpers for Sessions kanban grouping and labels. */

import type { SessionResponse } from '$lib/api/types';
import { coerceSessionStatus, SESSION_STATUSES, type SessionStatus } from '$lib/design/semantics';

export interface SessionColumn {
	status: SessionStatus;
	sessions: SessionResponse[];
}

export function shortId(id: string): string {
	if (id.length <= 8) return id;
	return id.slice(0, 8);
}

/** Prefer label, then branch, then truncated id. */
export function sessionDisplayLabel(session: SessionResponse): string {
	const label = session.label?.trim();
	if (label) return label;
	const branch = session.branch?.trim();
	if (branch) return branch;
	return shortId(session.id);
}

export function compareLastSeenDesc(a: SessionResponse, b: SessionResponse): number {
	const ta = Date.parse(a.last_seen_at);
	const tb = Date.parse(b.last_seen_at);
	const aOk = !Number.isNaN(ta);
	const bOk = !Number.isNaN(tb);
	if (aOk && bOk) return tb - ta;
	if (aOk) return -1;
	if (bOk) return 1;
	return 0;
}

/** Group sessions into kanban columns; each column sorted by last_seen_at desc. */
export function groupSessionsByStatus(sessions: SessionResponse[]): SessionColumn[] {
	const buckets: Record<SessionStatus, SessionResponse[]> = {
		working: [],
		waiting: [],
		blocked: [],
		completed: [],
		idle: []
	};

	for (const session of sessions) {
		const status = coerceSessionStatus(
			typeof session.status === 'string' ? session.status : undefined
		);
		buckets[status].push(session);
	}

	return SESSION_STATUSES.map((status) => ({
		status,
		sessions: [...buckets[status]].sort(compareLastSeenDesc)
	}));
}
