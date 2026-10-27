// Routing-table ordering, agent lookup and column selection contracts.
// Tests sortRules helpers with independent expected orders and state transitions.
// Depends on Vitest and routing response types.
import { expect, it } from 'vitest';
import type { RoutingRuleResponse } from '$lib/api/types';
import {
	buildAgentNameMap,
	compareRules,
	isRuleEnabled,
	nextSortState,
	resolveAgentName,
	sortRules
} from './sortRules';

function rule(
	partial: Partial<RoutingRuleResponse> & Pick<RoutingRuleResponse, 'id'>
): RoutingRuleResponse {
	return {
		owner_id: 'owner',
		channel: 'telegram',
		pattern: 'deploy',
		target_agent_id: 'agent-a',
		priority: 0,
		enabled: 1,
		created_at: '2026-07-21T00:00:00Z',
		...partial
	};
}

const keys = ['channel', 'pattern', 'target', 'priority', 'enabled'] as const;

it('isRuleEnabled treats non-zero as enabled', () => {
	for (const value of [-1, 1, 2]) {
		expect(isRuleEnabled(value)).toBe(true);
	}
	expect(isRuleEnabled(0)).toBe(false);
});

it('buildAgentNameMap / resolveAgentName maps id to name and returns null when missing', () => {
	const map = buildAgentNameMap([
		{ id: 'a1', name: 'alpha' },
		{ id: 'a2', name: 'beta' }
	]);
	expect(resolveAgentName(map, 'a1')).toBe('alpha');
	expect(resolveAgentName(map, 'a2')).toBe('beta');
	expect(resolveAgentName(map, 'missing')).toBeNull();
	expect(buildAgentNameMap([]).size).toBe(0);
});

it('sortRules orders every scalar column both ways without mutating input', () => {
	const rules = [
		rule({ id: 'low', priority: 1, channel: 'telegram', pattern: 'zebra', enabled: 1 }),
		rule({ id: 'high', priority: 10, channel: 'discord', pattern: 'middle', enabled: 1 }),
		rule({ id: 'mid', priority: 5, channel: 'email', pattern: 'Alpha', enabled: 0 })
	];
	const expected = [
		['priority', ['low', 'mid', 'high'], ['high', 'mid', 'low']],
		['channel', ['high', 'mid', 'low'], ['low', 'mid', 'high']],
		['pattern', ['mid', 'high', 'low'], ['low', 'high', 'mid']],
		['enabled', ['mid', 'high', 'low'], ['low', 'high', 'mid']]
	] as const;
	for (const [key, asc, desc] of expected) {
		expect(sortRules(rules, key, 'asc', new Map()).map((r) => r.id)).toEqual(asc);
		expect(sortRules(rules, key, 'desc', new Map()).map((r) => r.id)).toEqual(desc);
		expect(rules.map((r) => r.id)).toEqual(['low', 'high', 'mid']);
	}
});

it('sortRules sorts by target agent name when names are known', () => {
	const names = buildAgentNameMap([
		{ id: 'agent-a', name: 'zeta' },
		{ id: 'agent-b', name: 'alpha' }
	]);
	const rules = [
		rule({ id: 'r1', target_agent_id: 'agent-a' }),
		rule({ id: 'r2', target_agent_id: 'agent-b' }),
		rule({ id: 'r3', target_agent_id: 'mu' })
	];
	expect(sortRules(rules, 'target', 'asc', names).map((r) => r.id)).toEqual(['r2', 'r3', 'r1']);
	expect(sortRules(rules, 'target', 'desc', names).map((r) => r.id)).toEqual(['r1', 'r3', 'r2']);
});

it('sortRules breaks ties by id', () => {
	const a = rule({ id: 'a', priority: 5, pattern: 'Alpha' });
	const b = rule({ id: 'b', priority: 5, pattern: 'alpha' });
	for (const key of keys) {
		expect(compareRules(a, b, key, 'asc', new Map())).toBeLessThan(0);
		expect(compareRules(a, b, key, 'desc', new Map())).toBeGreaterThan(0);
		expect(compareRules(a, a, key, 'asc', new Map())).toBe(0);
	}
});

it('nextSortState toggles direction on same column', () => {
	for (const key of keys) {
		expect(nextSortState(key, 'desc', key)).toEqual({ key, dir: 'asc' });
		expect(nextSortState(key, 'asc', key)).toEqual({ key, dir: 'desc' });
	}
});

it('nextSortState defaults priority/enabled to desc when switching columns', () => {
	const defaults = [
		['channel', 'asc'],
		['pattern', 'asc'],
		['target', 'asc'],
		['priority', 'desc'],
		['enabled', 'desc']
	] as const;
	for (const current of keys) {
		for (const [key, dir] of defaults) {
			if (current === key) continue;
			for (const previous of ['asc', 'desc'] as const) {
				expect(nextSortState(current, previous, key)).toEqual({ key, dir });
			}
		}
	}
});
