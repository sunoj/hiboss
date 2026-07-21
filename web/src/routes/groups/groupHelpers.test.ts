import { describe, expect, it } from 'vitest';
import type { GroupResponse } from '$lib/api/types';
import {
	WRITE_DISABLED_NOTE,
	compareGroupsByName,
	displayDescription,
	hasDescription,
	memberCountLabel,
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

describe('WRITE_DISABLED_NOTE', () => {
	it('states the missing boss-scoped write endpoint', () => {
		expect(WRITE_DISABLED_NOTE).toBe('needs a boss-scoped write endpoint');
	});
});

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
