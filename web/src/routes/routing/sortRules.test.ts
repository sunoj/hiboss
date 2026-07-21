import { describe, expect, it } from 'vitest';
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

describe('isRuleEnabled', () => {
	it('treats non-zero as enabled', () => {
		expect(isRuleEnabled(1)).toBe(true);
		expect(isRuleEnabled(0)).toBe(false);
		expect(isRuleEnabled(2)).toBe(true);
	});
});

describe('buildAgentNameMap / resolveAgentName', () => {
	it('maps id to name and returns null when missing', () => {
		const map = buildAgentNameMap([
			{ id: 'a1', name: 'alpha' },
			{ id: 'a2', name: 'beta' }
		]);
		expect(resolveAgentName(map, 'a1')).toBe('alpha');
		expect(resolveAgentName(map, 'missing')).toBeNull();
	});
});

describe('sortRules', () => {
	it('orders by priority desc by default use-case', () => {
		const rules = [
			rule({ id: 'low', priority: 1 }),
			rule({ id: 'high', priority: 10 }),
			rule({ id: 'mid', priority: 5 })
		];
		const sorted = sortRules(rules, 'priority', 'desc', new Map());
		expect(sorted.map((r) => r.id)).toEqual(['high', 'mid', 'low']);
	});

	it('sorts by target agent name when names are known', () => {
		const names = buildAgentNameMap([
			{ id: 'agent-a', name: 'zeta' },
			{ id: 'agent-b', name: 'alpha' }
		]);
		const rules = [
			rule({ id: 'r1', target_agent_id: 'agent-a' }),
			rule({ id: 'r2', target_agent_id: 'agent-b' })
		];
		const sorted = sortRules(rules, 'target', 'asc', names);
		expect(sorted.map((r) => r.id)).toEqual(['r2', 'r1']);
	});

	it('breaks ties by id', () => {
		const a = rule({ id: 'a', priority: 5 });
		const b = rule({ id: 'b', priority: 5 });
		expect(compareRules(a, b, 'priority', 'asc', new Map())).toBeLessThan(0);
	});
});

describe('nextSortState', () => {
	it('toggles direction on same column', () => {
		expect(nextSortState('priority', 'desc', 'priority')).toEqual({
			key: 'priority',
			dir: 'asc'
		});
	});

	it('defaults priority/enabled to desc when switching columns', () => {
		expect(nextSortState('channel', 'asc', 'priority')).toEqual({
			key: 'priority',
			dir: 'desc'
		});
		expect(nextSortState('priority', 'desc', 'pattern')).toEqual({
			key: 'pattern',
			dir: 'asc'
		});
	});
});
