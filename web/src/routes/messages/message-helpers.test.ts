// Message query, filtering, session metadata and localized timestamp contracts.
// Depends on Vitest, real presentation helpers and the console locale state.
import { afterEach, describe, expect, it } from 'vitest';
import type { MessageResponse } from '$lib/api/types';
import { i18n } from '$lib/i18n';
import {
	DEFAULT_FILTERS, applyLocalFilters, buildMessagesQuery, formatAbsoluteTime, groupBySession,
	hasMorePages, sessionTitle, shortId, togglePriority, type MessageFilterState
} from './message-helpers';

afterEach(() => i18n.setLocale('en', false));

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

it('buildMessagesQuery maps all / non-inbox directions to direction=all', () => {
	for (const direction of ['all', 'boss_to_agent', 'agent_to_agent'] as const) {
		expect(buildMessagesQuery({ ...DEFAULT_FILTERS, direction }))
			.toEqual({ direction: 'all', limit: 50, offset: 0 });
	}
});
it('buildMessagesQuery maps agent_to_boss and joins multi priority', () => {
	const filters: MessageFilterState = {
		...DEFAULT_FILTERS, direction: 'agent_to_boss', priorities: ['critical', 'high'],
		agent: ' worker ', search: ' deploy ', session: ' s1 '
	};
	expect(buildMessagesQuery(filters)).toEqual({
		direction: 'agent_to_boss', priority: 'critical,high', agent: 'worker', search: 'deploy',
		session: 's1', limit: 50, offset: 0
	});
	expect(buildMessagesQuery(filters, { limit: 7, offset: 13 })).toEqual({
		direction: 'agent_to_boss', priority: 'critical,high', agent: 'worker', search: 'deploy',
		session: 's1', limit: 7, offset: 13
	});
	expect(buildMessagesQuery({ ...DEFAULT_FILTERS, agent: ' ', search: '\t', session: '\n' }))
		.toEqual({ direction: 'all', limit: 50, offset: 0 });
});

describe('applyLocalFilters', () => {
	const rows = [
		msg({ id: '1', direction: 'agent_to_boss', status: 'sent' }),
		msg({ id: '2', direction: 'boss_to_agent', status: 'replied' }),
		msg({ id: '3', direction: 'agent_to_agent', status: 'read' }),
		msg({ id: '4', direction: 'boss_to_agent', status: 'sent' }),
		msg({ id: '5', direction: 'agent_to_boss', status: 'replied' })
	];
	it('filters by direction and status client-side', () => {
		const cases = [
			['all', [['1', '2', '3', '4', '5'], ['1', '4'], ['2', '5'], ['3']]],
			['agent_to_boss', [['1', '5'], ['1'], ['5'], []]],
			['boss_to_agent', [['2', '4'], ['4'], ['2'], []]],
			['agent_to_agent', [['3'], [], [], ['3']]]
		] as const;
		for (const [direction, expected] of cases) {
			for (const [i, status] of (['all', 'sent', 'replied', 'read'] as const).entries()) {
				const filters = { ...DEFAULT_FILTERS, direction, status };
				expect(applyLocalFilters(rows, filters).map((m) => m.id)).toEqual(expected[i]);
			}
		}
	});
	it('passes through when filters are all', () => {
		expect(applyLocalFilters(rows, DEFAULT_FILTERS)).toEqual(rows);
	});
});

it('sessionTitle / shortId prefers label, then branch, then short id', () => {
	for (const [session_label, session_branch, session_id, expected] of [
		['hiboss/main', null, null, 'hiboss/main'], [null, 'feat/x', null, 'feat/x'],
		[null, null, 'abcdefghij', 'abcdefgh'], [null, null, null, 'No session'],
		[' A ', ' B ', 'abcdefghij', 'A'], [' \t', ' B ', null, 'B'], ['', '\n', ' abc ', 'abc']
	]) {
		expect(sessionTitle(msg({ id: '1', session_label, session_branch, session_id }))).toBe(expected);
	}
});
it('sessionTitle / shortId shortens long ids', () => {
	expect(shortId('abc')).toBe('abc');
	expect(shortId('abcdefghij', 4)).toBe('abcd');
});

it('groupBySession groups by session_id and orders by most recent activity', () => {
	const rows = [
		['old', 's1', 'A', 'working', '10'], ['new', 's2', 'B', 'waiting', '12'],
		['mid', 's1', 'A', 'blocked', '11'], ['last', 's1', 'C', 'completed', '13']
	].map(([id, session_id, session_label, session_status, hour]) => msg({
		id, session_id, session_label, session_status, created_at: `2026-07-21T${hour}:00:00Z`
	}));
	for (const [count, expected] of [
		[3, [['s2', 'B', 'waiting', '12', ['new']], ['s1', 'A', 'blocked', '11', ['old', 'mid']]]],
		[4, [['s1', 'C', 'completed', '13', ['old', 'mid', 'last']], ['s2', 'B', 'waiting', '12', ['new']]]]
	] as const) {
		expect(groupBySession(rows.slice(0, count)).map((g) => [
			g.key, g.title, g.status, g.latestAt, g.messages.map((m) => m.id)
		])).toEqual(expected.map(([key, title, status, hour, ids]) => [
			key, title, status, `2026-07-21T${hour}:00:00Z`, ids
		]));
	}
});
it('groupBySession buckets messages without session_id together', () => {
	const rows = [null, undefined, '', ' \t'].map((session_id, i) => msg({ id: String(i), session_id }));
	expect(groupBySession(rows)).toEqual([{
		key: '__none__', title: 'No session', status: 'idle', messages: rows,
		latestAt: '2026-07-21T12:00:00Z'
	}]);
});

it('togglePriority adds and removes priorities', () => {
	expect(togglePriority([], 'high')).toEqual(['high']);
	expect(togglePriority(['high', 'low'], 'high')).toEqual(['low']);
});

it('hasMorePages is true when loaded count is below total', () => {
	expect(hasMorePages(50, 120)).toBe(true);
	expect(hasMorePages(120, 120)).toBe(false);
	expect(hasMorePages(0, 0)).toBe(false);
});

it('formatAbsoluteTime returns em dash for invalid input', () => {
	for (const value of ['nope', '', '2026-13-01T00:00:00Z']) {
		expect(formatAbsoluteTime(value)).toBe('—');
	}
});
it('formatAbsoluteTime formats a valid ISO timestamp', () => {
	const iso = new Date(2026, 6, 21, 12, 34, 56).toISOString();
	for (const [locale, expected] of [
		['en', 'Jul 21, 2026, 12:34:56 PM'], ['zh-CN', '2026年7月21日 12:34:56']
	] as const) {
		i18n.setLocale(locale, false);
		expect(formatAbsoluteTime(iso)).toBe(expected);
		expect(formatAbsoluteTime(iso.replace('Z', '+00:00'))).toBe(expected);
	}
});
