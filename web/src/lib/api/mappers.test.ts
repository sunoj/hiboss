import { describe, expect, it } from 'vitest';
import {
	extractOptionMedia,
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

describe('extractOptionMedia', () => {
	it('returns empty array when metadata or option_media is missing', () => {
		expect(extractOptionMedia(null)).toEqual([]);
		expect(extractOptionMedia({})).toEqual([]);
		expect(extractOptionMedia({ options: ['A', 'B'] })).toEqual([]);
		expect(extractOptionMedia({ options: ['A', 'B'], option_media: undefined })).toEqual([]);
	});

	it('matches media to options by label and preserves options order', () => {
		const media = extractOptionMedia({
			options: ['Option A', 'Option B'],
			option_media: [
				{ label: 'Option B', url: 'https://example.com/b.png', caption: 'caption B' },
				{ label: 'Option A', url: 'https://example.com/a.png', caption: 'caption A' }
			]
		});
		expect(media).toEqual([
			{ label: 'Option A', url: 'https://example.com/a.png', caption: 'caption A' },
			{ label: 'Option B', url: 'https://example.com/b.png', caption: 'caption B' }
		]);
	});

	it('handles partial coverage (some options have media, others do not)', () => {
		const media = extractOptionMedia({
			options: ['Option A', 'Option B', 'Option C'],
			option_media: [
				{ label: 'Option A', url: 'https://example.com/a.png' },
				{ label: 'Option C', url: 'https://example.com/c.png', caption: 'caption C' }
			]
		});
		expect(media).toEqual([
			{ label: 'Option A', url: 'https://example.com/a.png', caption: undefined },
			{ label: 'Option C', url: 'https://example.com/c.png', caption: 'caption C' }
		]);
	});

	it('filters out media entries with invalid label or url', () => {
		const media = extractOptionMedia({
			options: ['Option A', 'Option B'],
			option_media: [
				{ label: 'Option A', url: 'https://example.com/a.png' },
				{ label: '', url: 'https://example.com/invalid.png' },
				{ label: 'Option B', url: 123 as unknown as string },
				{ label: 'Option C', url: 'https://example.com/c.png' }
			]
		});
		expect(media).toEqual([
			{ label: 'Option A', url: 'https://example.com/a.png', caption: undefined }
		]);
	});

	it('ignores media for labels not in options', () => {
		const media = extractOptionMedia({
			options: ['Option A'],
			option_media: [
				{ label: 'Option A', url: 'https://example.com/a.png' },
				{ label: 'Unknown Option', url: 'https://example.com/unknown.png' }
			]
		});
		expect(media).toEqual([{ label: 'Option A', url: 'https://example.com/a.png', caption: undefined }]);
	});

	it('trims label and caption whitespace', () => {
		const media = extractOptionMedia({
			options: ['  Option A  '],
			option_media: [
				{ label: '  Option A  ', url: 'https://example.com/a.png', caption: '  caption  ' }
			]
		});
		expect(media).toEqual([{ label: 'Option A', url: 'https://example.com/a.png', caption: 'caption' }]);
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
