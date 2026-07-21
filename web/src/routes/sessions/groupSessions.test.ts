import { describe, expect, it } from 'vitest';
import type { SessionResponse } from '$lib/api/types';
import {
	compareLastSeenDesc,
	groupSessionsByStatus,
	sessionDisplayLabel,
	shortId
} from './groupSessions';

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

describe('shortId', () => {
	it('truncates long ids to 8 chars', () => {
		expect(shortId('abcdefghijklmnop')).toBe('abcdefgh');
		expect(shortId('abc')).toBe('abc');
	});
});

describe('sessionDisplayLabel', () => {
	it('prefers label, then branch, then short id', () => {
		expect(sessionDisplayLabel(session({ id: 'abcdefgh', label: 'feat-x' }))).toBe('feat-x');
		expect(sessionDisplayLabel(session({ id: 'abcdefgh', branch: 'main' }))).toBe('main');
		expect(sessionDisplayLabel(session({ id: 'abcdefghijklmnop' }))).toBe('abcdefgh');
	});
});

describe('compareLastSeenDesc', () => {
	it('orders newer last_seen_at first', () => {
		const older = session({ id: 'a', last_seen_at: '2026-07-20T00:00:00Z' });
		const newer = session({ id: 'b', last_seen_at: '2026-07-21T12:00:00Z' });
		expect(compareLastSeenDesc(newer, older)).toBeLessThan(0);
		expect([older, newer].sort(compareLastSeenDesc).map((s) => s.id)).toEqual(['b', 'a']);
	});
});

describe('groupSessionsByStatus', () => {
	it('buckets by coerced status and sorts within columns', () => {
		const sessions = [
			session({ id: 'w1', status: 'working', last_seen_at: '2026-07-21T01:00:00Z' }),
			session({ id: 'w2', status: 'working', last_seen_at: '2026-07-21T03:00:00Z' }),
			session({ id: 'wait', status: 'waiting', last_seen_at: '2026-07-21T02:00:00Z' }),
			session({ id: 'bogus', status: 'zombie', last_seen_at: '2026-07-21T04:00:00Z' })
		];

		const columns = groupSessionsByStatus(sessions);
		expect(columns.map((c) => c.status)).toEqual([
			'working',
			'waiting',
			'blocked',
			'completed',
			'idle'
		]);
		expect(columns[0].sessions.map((s) => s.id)).toEqual(['w2', 'w1']);
		expect(columns[1].sessions.map((s) => s.id)).toEqual(['wait']);
		expect(columns[2].sessions).toHaveLength(0);
		expect(columns[3].sessions).toHaveLength(0);
		expect(columns[4].sessions.map((s) => s.id)).toEqual(['bogus']);
	});
});
