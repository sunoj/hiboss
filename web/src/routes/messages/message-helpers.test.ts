import { describe, expect, it } from 'vitest';
import type { MessageResponse } from '$lib/api/types';
import {
	DEFAULT_FILTERS,
	PAGE_SIZE,
	applyLocalFilters,
	buildMessagesQuery,
	formatAbsoluteTime,
	groupBySession,
	hasMorePages,
	sessionTitle,
	shortId,
	togglePriority,
	type MessageFilterState
} from './message-helpers';

function msg(partial: Partial<MessageResponse> & { id: string }): MessageResponse {
	return {
		agent_id: 'a1',
		direction: 'agent_to_boss',
		mode: 'async',
		channel: 'api',
		body: 'hello',
		status: 'sent',
		reply_to: null,
		priority: 'normal',
		type: null,
		metadata: null,
		created_at: '2026-07-21T12:00:00Z',
		updated_at: '2026-07-21T12:00:00Z',
		...partial
	};
}

describe('buildMessagesQuery', () => {
	it('maps all / non-inbox directions to direction=all', () => {
		expect(buildMessagesQuery({ ...DEFAULT_FILTERS, direction: 'all' }).direction).toBe('all');
		expect(
			buildMessagesQuery({ ...DEFAULT_FILTERS, direction: 'boss_to_agent' }).direction
		).toBe('all');
		expect(
			buildMessagesQuery({ ...DEFAULT_FILTERS, direction: 'agent_to_agent' }).direction
		).toBe('all');
	});

	it('maps agent_to_boss and joins multi priority', () => {
		const q = buildMessagesQuery({
			...DEFAULT_FILTERS,
			direction: 'agent_to_boss',
			priorities: ['critical', 'high'],
			agent: ' worker ',
			search: ' deploy ',
			session: 's1'
		});
		expect(q.direction).toBe('agent_to_boss');
		expect(q.priority).toBe('critical,high');
		expect(q.agent).toBe('worker');
		expect(q.search).toBe('deploy');
		expect(q.session).toBe('s1');
		expect(q.limit).toBe(50);
	});
});

describe('applyLocalFilters', () => {
	const rows = [
		msg({ id: '1', direction: 'agent_to_boss', status: 'sent' }),
		msg({ id: '2', direction: 'boss_to_agent', status: 'replied' }),
		msg({ id: '3', direction: 'agent_to_agent', status: 'read' })
	];

	it('filters by direction and status client-side', () => {
		const filters: MessageFilterState = {
			...DEFAULT_FILTERS,
			direction: 'boss_to_agent',
			status: 'replied'
		};
		expect(applyLocalFilters(rows, filters).map((m) => m.id)).toEqual(['2']);
	});

	it('passes through when filters are all', () => {
		expect(applyLocalFilters(rows, DEFAULT_FILTERS)).toHaveLength(3);
	});
});

describe('sessionTitle / shortId', () => {
	it('prefers label, then branch, then short id', () => {
		expect(sessionTitle(msg({ id: '1', session_label: 'hiboss/main' }))).toBe('hiboss/main');
		expect(sessionTitle(msg({ id: '2', session_branch: 'feat/x' }))).toBe('feat/x');
		expect(sessionTitle(msg({ id: '3', session_id: 'abcdefghij' }))).toBe('abcdefgh');
		expect(sessionTitle(msg({ id: '4' }))).toBe('No session');
	});

	it('shortens long ids', () => {
		expect(shortId('abc')).toBe('abc');
		expect(shortId('abcdefghij', 4)).toBe('abcd');
	});
});

describe('groupBySession', () => {
	it('groups by session_id and orders by most recent activity', () => {
		const groups = groupBySession([
			msg({
				id: 'old',
				session_id: 's1',
				session_label: 'A',
				session_status: 'working',
				created_at: '2026-07-21T10:00:00Z'
			}),
			msg({
				id: 'new',
				session_id: 's2',
				session_label: 'B',
				session_status: 'waiting',
				created_at: '2026-07-21T12:00:00Z'
			}),
			msg({
				id: 'mid',
				session_id: 's1',
				session_label: 'A',
				session_status: 'blocked',
				created_at: '2026-07-21T11:00:00Z'
			})
		]);
		expect(groups.map((g) => g.key)).toEqual(['s2', 's1']);
		expect(groups[1].messages).toHaveLength(2);
		expect(groups[1].status).toBe('blocked');
		expect(groups[1].title).toBe('A');
	});

	it('buckets messages without session_id together', () => {
		const groups = groupBySession([msg({ id: 'x' }), msg({ id: 'y' })]);
		expect(groups).toHaveLength(1);
		expect(groups[0].key).toBe('__none__');
		expect(groups[0].title).toBe('No session');
	});
});

describe('togglePriority', () => {
	it('adds and removes priorities', () => {
		expect(togglePriority([], 'high')).toEqual(['high']);
		expect(togglePriority(['high', 'low'], 'high')).toEqual(['low']);
	});
});

describe('hasMorePages', () => {
	it('is true when loaded count is below total', () => {
		expect(hasMorePages(50, 120)).toBe(true);
		expect(hasMorePages(120, 120)).toBe(false);
		expect(hasMorePages(0, 0)).toBe(false);
	});
});

describe('formatAbsoluteTime', () => {
	it('returns em dash for invalid input', () => {
		expect(formatAbsoluteTime('nope')).toBe('—');
	});

	it('formats a valid ISO timestamp', () => {
		const out = formatAbsoluteTime('2026-07-21T12:00:00Z');
		expect(out).not.toBe('—');
		expect(out.length).toBeGreaterThan(4);
	});
});
