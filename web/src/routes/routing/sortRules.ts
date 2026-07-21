/** Pure helpers for Routing rules table sort and agent name lookup. */

import type { RoutingRuleResponse } from '$lib/api/types';

export type RuleSortKey = 'channel' | 'pattern' | 'target' | 'priority' | 'enabled';
export type SortDir = 'asc' | 'desc';

export const WRITE_NOTE = 'needs a boss-scoped write endpoint';

export function isRuleEnabled(enabled: number): boolean {
	return enabled !== 0;
}

export function buildAgentNameMap(agents: ReadonlyArray<{ id: string; name: string }>): Map<string, string> {
	const map = new Map<string, string>();
	for (const agent of agents) {
		map.set(agent.id, agent.name);
	}
	return map;
}

export function resolveAgentName(map: Map<string, string>, agentId: string): string | null {
	return map.get(agentId) ?? null;
}

function cmpString(a: string, b: string): number {
	return a.localeCompare(b, undefined, { sensitivity: 'base' });
}

function valueFor(
	rule: RoutingRuleResponse,
	key: RuleSortKey,
	names: Map<string, string>
): string | number {
	switch (key) {
		case 'channel':
			return rule.channel;
		case 'pattern':
			return rule.pattern;
		case 'target':
			return names.get(rule.target_agent_id) ?? rule.target_agent_id;
		case 'priority':
			return rule.priority;
		case 'enabled':
			return rule.enabled;
	}
}

export function compareRules(
	a: RoutingRuleResponse,
	b: RoutingRuleResponse,
	key: RuleSortKey,
	dir: SortDir,
	names: Map<string, string>
): number {
	const av = valueFor(a, key, names);
	const bv = valueFor(b, key, names);
	let result: number;
	if (typeof av === 'number' && typeof bv === 'number') {
		result = av - bv;
	} else {
		result = cmpString(String(av), String(bv));
	}
	if (result === 0) result = cmpString(a.id, b.id);
	return dir === 'asc' ? result : -result;
}

/** Stable sort; default use-case is priority desc. */
export function sortRules(
	rules: readonly RoutingRuleResponse[],
	key: RuleSortKey,
	dir: SortDir,
	names: Map<string, string>
): RoutingRuleResponse[] {
	return [...rules].sort((a, b) => compareRules(a, b, key, dir, names));
}

/** Toggle direction when re-clicking the same column; else pick a sensible default. */
export function nextSortState(
	currentKey: RuleSortKey,
	currentDir: SortDir,
	clicked: RuleSortKey
): { key: RuleSortKey; dir: SortDir } {
	if (currentKey === clicked) {
		return { key: clicked, dir: currentDir === 'asc' ? 'desc' : 'asc' };
	}
	return { key: clicked, dir: clicked === 'priority' || clicked === 'enabled' ? 'desc' : 'asc' };
}
