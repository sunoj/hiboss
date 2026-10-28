// Session labels, invalid timestamps and complete status grouping contracts.
// Depends on Vitest and the Sessions presentation helpers.
import { expect, it } from 'vitest';
import type { SessionResponse } from '$lib/api/types';
import { compareLastSeenDesc, groupSessionsByStatus, sessionDisplayLabel, shortId } from './groupSessions';

function session(partial: Partial<SessionResponse> & Pick<SessionResponse, 'id'>): SessionResponse {
	return {
		label: null,
		branch: null,
		cwd: null,
		status: 'idle',
		status_text: null,
		agent_name: null,
		last_seen_at: '2026-07-21T00:00:00Z',
		started_at: null,
		...partial
	};
}

it('shortId truncates long ids to 8 chars', () => {
	for (const [id, expected] of [
		['', ''], ['abc', 'abc'], ['abcdefg', 'abcdefg'], ['abcdefgh', 'abcdefgh'],
		['abcdefghi', 'abcdefgh'], ['abcdefghijklmnop', 'abcdefgh']
	]) {
		expect(shortId(id)).toBe(expected);
	}
});

it('sessionDisplayLabel uses the canonical slug and full branch over a stale label', () => {
	for (const [branch, expected] of [['feat/a', 'repo/feat/a'], [null, 'repo'], ['', 'repo']]) {
		expect(sessionDisplayLabel(session({ id: 's', project_slug: 'repo', branch, label: 'old/main' })))
			.toBe(expected);
	}
});

it('sessionDisplayLabel prefers label, then branch, then short id', () => {
	const rows = [
		['feat-x', null, 'feat-x'], [null, 'main', 'main'], [null, null, 'abcdefgh'],
		['  feat-x \n', 'main', 'feat-x'], [' \t', ' main ', 'main'], ['', '\n', 'abcdefgh']
	];
	for (const [label, branch, expected] of rows) {
		expect(sessionDisplayLabel(session({ id: 'abcdefghijklmnop', project_slug: '', label, branch })))
			.toBe(expected);
	}
});

it('compareLastSeenDesc orders newer last_seen_at first', () => {
	const rows = ['invalid', '2026-07-20T00:00:00Z', '2026-07-21T12:00:00Z', ''].map(
		(last_seen_at, i) => session({ id: String(i), last_seen_at })
	);
	expect(compareLastSeenDesc(rows[2], rows[1])).toBeLessThan(0);
	expect(compareLastSeenDesc(rows[1], rows[2])).toBeGreaterThan(0);
	expect([...rows].sort(compareLastSeenDesc).map((s) => s.id)).toEqual(['2', '1', '0', '3']);
	expect(compareLastSeenDesc(rows[0], rows[3])).toBe(0);
	expect(compareLastSeenDesc(rows[1], rows[1])).toBe(0);
	expect(compareLastSeenDesc(rows[2], session({
		id: 'offset', last_seen_at: '2026-07-21T14:00:00+02:00'
	}))).toBe(0);
});

it('groupSessionsByStatus buckets by coerced status and sorts within columns', () => {
	const statuses = ['working', 'waiting', 'blocked', 'completed', 'idle'];
	const rows = ['zombie', ...statuses, 'working'].map((status, i) => Object.freeze(session({
		id: String(i), status, last_seen_at: `2026-07-21T0${i}:00:00Z`
	})));
	Object.freeze(rows);
	const columns = groupSessionsByStatus(rows);
	expect(columns.map((c) => [c.status, c.sessions.map((s) => s.id)])).toEqual([
		['working', ['6', '1']], ['waiting', ['2']], ['blocked', ['3']],
		['completed', ['4']], ['idle', ['5', '0']]
	]);
	expect(groupSessionsByStatus([])).toEqual(statuses.map((status) => ({ status, sessions: [] })));
});
