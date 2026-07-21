import { describe, expect, it } from 'vitest';
import type { AgentResponse, GroupResponse } from '$lib/api/types';
import {
	agentOptionLabel,
	broadcastResultLabel,
	canCreateGroup,
	canSendBroadcast,
	compareAgentsByName,
	compareGroupsByName,
	displayDescription,
	hasDescription,
	memberCountLabel,
	sortAgentsByName,
	sortGroupsByName
} from './groupHelpers';

function group(partial: Partial<GroupResponse> & Pick<GroupResponse, 'id' | 'name'>): GroupResponse {
	return {
		description: null,
		created_at: '2026-07-21T00:00:00Z',
		member_count: 0,
		...partial
	};
}

function agent(
	partial: Partial<AgentResponse> & Pick<AgentResponse, 'id' | 'name'>
): AgentResponse {
	return {
		role: null,
		last_used_at: null,
		created_at: '2026-07-21T00:00:00Z',
		...partial
	};
}

describe('compareGroupsByName / sortGroupsByName', () => {
	it('orders by name case-insensitively', () => {
		const a = group({ id: '1', name: 'zeta' });
		const b = group({ id: '2', name: 'Alpha' });
		const c = group({ id: '3', name: 'beta' });
		expect(compareGroupsByName(b, a)).toBeLessThan(0);
		expect(sortGroupsByName([a, b, c]).map((g) => g.id)).toEqual(['2', '3', '1']);
	});

	it('does not mutate the input array', () => {
		const input = [group({ id: '1', name: 'b' }), group({ id: '2', name: 'a' })];
		const sorted = sortGroupsByName(input);
		expect(input.map((g) => g.id)).toEqual(['1', '2']);
		expect(sorted.map((g) => g.id)).toEqual(['2', '1']);
	});
});

describe('sortAgentsByName', () => {
	it('orders agents by name', () => {
		const a = agent({ id: '1', name: 'zeta' });
		const b = agent({ id: '2', name: 'Alpha' });
		expect(compareAgentsByName(b, a)).toBeLessThan(0);
		expect(sortAgentsByName([a, b]).map((x) => x.id)).toEqual(['2', '1']);
	});
});

describe('memberCountLabel', () => {
	it('singularizes one member', () => {
		expect(memberCountLabel(1)).toBe('1 member');
		expect(memberCountLabel(0)).toBe('0 members');
		expect(memberCountLabel(3)).toBe('3 members');
	});
});

describe('displayDescription / hasDescription', () => {
	it('falls back when description is null or blank', () => {
		expect(displayDescription(null)).toBe('No description');
		expect(displayDescription('   ')).toBe('No description');
		expect(displayDescription('Ops agents')).toBe('Ops agents');
		expect(hasDescription(null)).toBe(false);
		expect(hasDescription('x')).toBe(true);
	});
});

describe('canCreateGroup', () => {
	it('requires non-empty name and owner', () => {
		expect(canCreateGroup('', 'a1')).toBe(false);
		expect(canCreateGroup('  ', 'a1')).toBe(false);
		expect(canCreateGroup('Ops', '')).toBe(false);
		expect(canCreateGroup('Ops', 'a1')).toBe(true);
	});
});

describe('agentOptionLabel', () => {
	it('includes name and short id', () => {
		expect(agentOptionLabel({ id: 'abcdefghij', name: 'Coder' })).toBe('Coder (abcdefgh)');
		expect(agentOptionLabel({ id: 'short', name: 'Bot' })).toBe('Bot (short)');
	});
});

describe('broadcastResultLabel / canSendBroadcast', () => {
	it('reports delivery count', () => {
		expect(broadcastResultLabel(0)).toBe('Broadcast delivered to 0 agents');
		expect(broadcastResultLabel(1)).toBe('Broadcast delivered to 1 agent');
		expect(broadcastResultLabel(4)).toBe('Broadcast delivered to 4 agents');
	});

	it('requires group and body', () => {
		expect(canSendBroadcast('', 'hi')).toBe(false);
		expect(canSendBroadcast('g1', '  ')).toBe(false);
		expect(canSendBroadcast('g1', 'hello')).toBe(true);
	});
});
