/** Pure helpers for the Agents list and detail drawer. */

import { formatRelativeTime } from '$lib/api/mappers';
import type { AgentResponse } from '$lib/api/types';

export function shortId(id: string): string {
	if (id.length <= 8) return id;
	return id.slice(0, 8);
}

export function roleLabel(role: string | null | undefined): string {
	const trimmed = role?.trim();
	return trimmed && trimmed.length > 0 ? trimmed : '—';
}

/** Relative last-used label; null/invalid → "Never". */
export function lastUsedLabel(iso: string | null | undefined, nowMs = Date.now()): string {
	if (!iso || !iso.trim()) return 'Never';
	const label = formatRelativeTime(iso, nowMs);
	return label === '—' ? 'Never' : label;
}

export function compareLastUsedDesc(a: AgentResponse, b: AgentResponse): number {
	const ta = a.last_used_at ? Date.parse(a.last_used_at) : Number.NaN;
	const tb = b.last_used_at ? Date.parse(b.last_used_at) : Number.NaN;
	const aOk = !Number.isNaN(ta);
	const bOk = !Number.isNaN(tb);
	if (aOk && bOk) return tb - ta;
	if (aOk) return -1;
	if (bOk) return 1;
	return a.name.localeCompare(b.name);
}

/** Newest last_used_at first; never-used agents last, then by name. */
export function sortAgentsByLastUsed(agents: AgentResponse[]): AgentResponse[] {
	return [...agents].sort(compareLastUsedDesc);
}
