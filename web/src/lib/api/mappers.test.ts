import { describe, expect, it } from 'vitest';
import {
	extractOptions,
	formatRelativeTime,
	normalizeMessage,
	priorityBarWidths,
	sessionStatusEntries,
	truncateBody
} from './mappers';

describe('extractOptions', () => {
	it('keeps options with commas intact (never splits on comma)', () => {
		expect(extractOptions({ options: ['Ship it, now', 'Wait, then retry'] })).toEqual([
			'Ship it, now',
			'Wait, then retry'
		]);
	});

	it('reads label from object-shaped options and drops empties', () => {
		expect(extractOptions({ options: [{ label: 'Approve' }, { label: '' }, 'Reject'] })).toEqual([
			'Approve',
			'Reject'
		]);
	});

	it('returns [] when metadata or options are missing or not an array', () => {
		expect(extractOptions(null)).toEqual([]);
		expect(extractOptions({})).toEqual([]);
		expect(extractOptions({ options: 'A,B' as unknown as string[] })).toEqual([]);
	});
});

describe('normalizeMessage', () => {
	it('maps session context fields through', () => {
		const m = normalizeMessage({
			id: 'm1',
			body: 'hi',
			created_at: '2026-07-21T00:00:00Z',
			session_id: 's1',
			session_label: 'hiboss/main',
			session_branch: 'main',
			session_status: 'working'
		});
		expect(m.session_label).toBe('hiboss/main');
		expect(m.session_branch).toBe('main');
		expect(m.session_status).toBe('working');
	});

	it('falls back to safe defaults for unknown enums and null session', () => {
		const m = normalizeMessage({ id: 'm2', direction: 'sideways', priority: 'bogus' });
		expect(m.direction).toBe('agent_to_boss');
		expect(m.priority).toBe('normal');
		expect(m.session_label).toBeNull();
	});
});

describe('priorityBarWidths', () => {
	it('orders critical→low and computes percentages', () => {
		const rows = priorityBarWidths({ critical: 1, high: 1, normal: 2, low: 0 });
		expect(rows.map((r) => r.priority)).toEqual(['critical', 'high', 'normal', 'low']);
		expect(rows[2]).toMatchObject({ count: 2, pct: 50 });
	});

	it('returns 0% for an empty distribution without dividing by zero', () => {
		expect(priorityBarWidths({ critical: 0, high: 0, normal: 0, low: 0 })[0].pct).toBe(0);
	});
});

describe('sessionStatusEntries', () => {
	it('lists known statuses first, then appends extras', () => {
		const rows = sessionStatusEntries({ working: 3, custom: 1 });
		expect(rows[0]).toEqual({ status: 'working', count: 3 });
		expect(rows.at(-1)).toEqual({ status: 'custom', count: 1 });
	});
});

describe('formatRelativeTime', () => {
	const now = Date.parse('2026-07-21T12:00:00Z');
	it('formats seconds, minutes, hours, and days', () => {
		expect(formatRelativeTime('2026-07-21T11:59:30Z', now)).toBe('30 seconds ago');
		expect(formatRelativeTime('2026-07-21T11:30:00Z', now)).toBe('30 minutes ago');
		expect(formatRelativeTime('2026-07-21T09:00:00Z', now)).toBe('3 hours ago');
		expect(formatRelativeTime('2026-07-19T12:00:00Z', now)).toBe('2 days ago');
	});

	it('returns an em dash for unparseable input', () => {
		expect(formatRelativeTime('not-a-date', now)).toBe('—');
	});
});

describe('truncateBody', () => {
	it('collapses whitespace and truncates with an ellipsis', () => {
		expect(truncateBody('a\n  b   c')).toBe('a b c');
		expect(truncateBody('abcdef', 4)).toBe('abc…');
	});
});
