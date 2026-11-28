import { describe, expect, it } from 'vitest';
import type { AgentResponse } from '$lib/api/types';
import {
	agentConfig,
	buildConfigUpdate,
	compareLastUsedDesc,
	defaultAgentConfig,
	lastUsedLabel,
	parseRateLimitInput,
	rateLimitToInput,
	roleLabel,
	shortId,
	sortAgentsByLastUsed
} from './agent-helpers';

function agent(partial: Partial<AgentResponse> & Pick<AgentResponse, 'id' | 'name'>): AgentResponse {
	return {
		role: null,
		last_used_at: null,
		created_at: '2026-07-01T00:00:00Z',
		...partial
	};
}

describe('shortId', () => {
	it('truncates long ids to 8 chars', () => {
		expect(shortId('abcdefghijklmnop')).toBe('abcdefgh');
		expect(shortId('abc')).toBe('abc');
	});
});

describe('roleLabel', () => {
	it('returns em dash for empty roles', () => {
		expect(roleLabel(null)).toBe('—');
		expect(roleLabel('')).toBe('—');
		expect(roleLabel('  ')).toBe('—');
	});

	it('returns trimmed role text', () => {
		expect(roleLabel(' worker ')).toBe('worker');
	});
});

describe('lastUsedLabel', () => {
	const now = Date.parse('2026-07-21T12:00:00Z');

	it('returns Never for missing or invalid timestamps', () => {
		expect(lastUsedLabel(null, now)).toBe('Never');
		expect(lastUsedLabel('', now)).toBe('Never');
		expect(lastUsedLabel('not-a-date', now)).toBe('Never');
	});

	it('delegates valid timestamps to formatRelativeTime', () => {
		expect(lastUsedLabel('2026-07-21T11:30:00Z', now)).toBe('30 minutes ago');
	});
});

describe('compareLastUsedDesc / sortAgentsByLastUsed', () => {
	it('orders newer last_used_at first and never-used last', () => {
		const older = agent({ id: 'a', name: 'Alpha', last_used_at: '2026-07-20T00:00:00Z' });
		const newer = agent({ id: 'b', name: 'Bravo', last_used_at: '2026-07-21T12:00:00Z' });
		const never = agent({ id: 'c', name: 'Charlie', last_used_at: null });

		expect(compareLastUsedDesc(newer, older)).toBeLessThan(0);
		expect(sortAgentsByLastUsed([older, never, newer]).map((a) => a.id)).toEqual([
			'b',
			'a',
			'c'
		]);
	});

	it('falls back to name when both lack last_used_at', () => {
		const a = agent({ id: '1', name: 'Zed', last_used_at: null });
		const b = agent({ id: '2', name: 'Ann', last_used_at: null });
		expect(sortAgentsByLastUsed([a, b]).map((x) => x.name)).toEqual(['Ann', 'Zed']);
	});
});

describe('parseRateLimitInput / rateLimitToInput', () => {
	it('parses empty as null and rejects invalid', () => {
		expect(parseRateLimitInput('')).toBeNull();
		expect(parseRateLimitInput('  ')).toBeNull();
		expect(parseRateLimitInput('12')).toBe(12);
		expect(parseRateLimitInput('0')).toBe(0);
		expect(parseRateLimitInput('-1')).toBeUndefined();
		expect(parseRateLimitInput('1.5')).toBeUndefined();
		expect(parseRateLimitInput('abc')).toBeUndefined();
	});

	it('round-trips null/number for the input field', () => {
		expect(rateLimitToInput(null)).toBe('');
		expect(rateLimitToInput(7)).toBe('7');
	});
});

describe('buildConfigUpdate', () => {
	it('builds a valid update body', () => {
		const res = buildConfigUpdate({
			default_priority: 'high',
			rateLimitRaw: '10'
		});
		expect(res).toEqual({
			ok: true,
			body: {
				default_priority: 'high',
				rate_limit: 10
			}
		});
	});

	it('rejects bad rate limit', () => {
		const res = buildConfigUpdate({
			default_priority: 'normal',
			rateLimitRaw: 'nope'
		});
		expect(res.ok).toBe(false);
	});
});

describe('defaultAgentConfig', () => {
	it('returns normal defaults', () => {
		expect(defaultAgentConfig()).toEqual({
			default_priority: 'normal',
			rate_limit: null
		});
	});
});

describe('agent sending defaults from the inventory', () => {
	const row: AgentResponse = {
		id: 'fixture', name: 'Builder', role: 'builder', last_used_at: null, created_at: '2026-09-12T00:00:00Z'
	};
	it('preserves the legacy blank defaults', () => {
		expect(agentConfig(row)).toEqual(defaultAgentConfig());
	});
	it('uses all supported server fields and preserves a zero rate limit', () => {
		const config = { default_priority: 'high', rate_limit: 0 } as const;
		expect(agentConfig({ ...row, ...config })).toEqual(config);
	});
});
