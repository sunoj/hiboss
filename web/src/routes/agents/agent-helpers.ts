/** Pure helpers for the Agents list and detail drawer. */

import { formatRelativeTime } from '$lib/api/mappers';
import type {
	AgentConfigResponse,
	AgentConfigUpdateRequest,
	AgentResponse,
	Channel
} from '$lib/api/types';
import { PRIORITIES, type Priority } from '$lib/design/semantics';

export const AGENT_CHANNELS: readonly Channel[] = ['discord', 'telegram', 'email', 'api'];

export type RoutingEntry = { key: string; channel: Channel };

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

export function isAgentChannel(value: string): value is Channel {
	return (AGENT_CHANNELS as readonly string[]).includes(value);
}

/** Defaults when boss list has no config payload yet. */
export function defaultAgentConfig(): AgentConfigResponse {
	return { default_priority: 'normal', rate_limit: null, channel_routing: null };
}

export function rateLimitToInput(value: number | null | undefined): string {
	return value === null || value === undefined ? '' : String(value);
}

/** Empty → null; invalid → undefined (caller should reject). */
export function parseRateLimitInput(raw: string): number | null | undefined {
	const trimmed = raw.trim();
	if (trimmed === '') return null;
	if (!/^\d+$/.test(trimmed)) return undefined;
	const n = Number(trimmed);
	if (!Number.isInteger(n) || n < 0) return undefined;
	return n;
}

export function routingEntriesFromMap(
	map: Record<string, Channel> | null | undefined
): RoutingEntry[] {
	if (!map) return [];
	return Object.entries(map).map(([key, channel]) => ({ key, channel }));
}

export function routingMapFromEntries(entries: RoutingEntry[]): Record<string, Channel> | null {
	const out: Record<string, Channel> = {};
	for (const entry of entries) {
		const key = entry.key.trim();
		if (!key) continue;
		out[key] = entry.channel;
	}
	return Object.keys(out).length > 0 ? out : null;
}

export function buildConfigUpdate(input: {
	default_priority: Priority;
	rateLimitRaw: string;
	routing: RoutingEntry[];
}): { ok: true; body: AgentConfigUpdateRequest } | { ok: false; error: string } {
	if (!(PRIORITIES as readonly string[]).includes(input.default_priority)) {
		return { ok: false, error: 'Invalid default priority' };
	}
	const rate_limit = parseRateLimitInput(input.rateLimitRaw);
	if (rate_limit === undefined) {
		return { ok: false, error: 'Rate limit must be a non-negative integer or empty' };
	}
	for (const entry of input.routing) {
		if (!isAgentChannel(entry.channel)) {
			return { ok: false, error: 'Invalid channel in routing' };
		}
	}
	return {
		ok: true,
		body: {
			default_priority: input.default_priority,
			rate_limit,
			channel_routing: routingMapFromEntries(input.routing)
		}
	};
}
