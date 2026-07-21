import { describe, expect, it } from 'vitest';
import type { AuditEntry } from '$lib/api/types';
import {
	applyLocalSearch,
	buildAuditQuery,
	canGoNext,
	canGoPrev,
	clampLimit,
	clampOffset,
	formatPageLabel,
	formatResource,
	nextOffset,
	pageRange,
	prevOffset,
	resetOffset,
	shortId,
	truncateDetails,
	type AuditFilterState
} from './audit-helpers';

function entry(partial: Partial<AuditEntry> & Pick<AuditEntry, 'id'>): AuditEntry {
	return {
		actor_type: 'agent',
		actor_id: 'agent-1',
		action: 'message.send',
		resource_type: 'message',
		resource_id: 'msg-12345678',
		details: null,
		created_at: '2026-07-21T12:00:00Z',
		...partial
	};
}

const baseFilters: AuditFilterState = {
	actor_type: 'all',
	action: '',
	search: '',
	limit: 50,
	offset: 0
};

describe('clampLimit / clampOffset', () => {
	it('clamps limit to 1..200 with default for invalid', () => {
		expect(clampLimit(25)).toBe(25);
		expect(clampLimit(500)).toBe(200);
		expect(clampLimit(0)).toBe(50);
		expect(clampLimit(NaN)).toBe(50);
	});

	it('floors offset at 0', () => {
		expect(clampOffset(10)).toBe(10);
		expect(clampOffset(-3)).toBe(0);
		expect(clampOffset(1.9)).toBe(1);
	});
});

describe('buildAuditQuery', () => {
	it('omits empty actor_type and action', () => {
		expect(buildAuditQuery(baseFilters)).toEqual({ limit: 50, offset: 0 });
	});

	it('includes actor_type and trimmed action', () => {
		expect(
			buildAuditQuery({
				...baseFilters,
				actor_type: 'boss',
				action: '  message.reply  ',
				limit: 100,
				offset: 20
			})
		).toEqual({
			actor_type: 'boss',
			action: 'message.reply',
			limit: 100,
			offset: 20
		});
	});
});

describe('applyLocalSearch', () => {
	const rows = [
		entry({ id: 'a', action: 'message.send', actor_id: 'alice', details: 'discord' }),
		entry({ id: 'b', action: 'boss.grant', actor_type: 'boss', actor_id: 'boss-1' }),
		entry({
			id: 'c',
			action: 'channel.set',
			resource_type: 'channel_config',
			resource_id: 'cc-99',
			details: 'telegram'
		})
	];

	it('returns all when search is blank', () => {
		expect(applyLocalSearch(rows, '  ')).toHaveLength(3);
	});

	it('matches action, actor, resource, and details', () => {
		expect(applyLocalSearch(rows, 'GRANT').map((e) => e.id)).toEqual(['b']);
		expect(applyLocalSearch(rows, 'alice').map((e) => e.id)).toEqual(['a']);
		expect(applyLocalSearch(rows, 'telegram').map((e) => e.id)).toEqual(['c']);
		expect(applyLocalSearch(rows, 'channel_config').map((e) => e.id)).toEqual(['c']);
	});
});

describe('pagination helpers', () => {
	it('prev/next and canGo flags', () => {
		expect(canGoPrev(0)).toBe(false);
		expect(canGoPrev(50)).toBe(true);
		expect(prevOffset(50, 50)).toBe(0);
		expect(nextOffset(0, 50)).toBe(50);
		expect(canGoNext(0, 50, 120)).toBe(true);
		expect(canGoNext(100, 50, 120)).toBe(false);
	});

	it('formats page range labels', () => {
		expect(pageRange(0, 50, 120, 50)).toEqual({ from: 1, to: 50, total: 120 });
		expect(pageRange(100, 50, 120, 20)).toEqual({ from: 101, to: 120, total: 120 });
		expect(formatPageLabel(0, 50, 0, 0)).toBe('0 of 0');
		expect(formatPageLabel(0, 50, 120, 50)).toBe('1–50 of 120');
	});

	it('resetOffset clears offset only', () => {
		expect(resetOffset({ ...baseFilters, offset: 75, search: 'x' })).toEqual({
			...baseFilters,
			offset: 0,
			search: 'x'
		});
	});
});

describe('format helpers', () => {
	it('shortId and formatResource', () => {
		expect(shortId('abcdefghijklmnop')).toBe('abcdefgh');
		expect(formatResource('message', 'msg-12345678abcd')).toBe('message:msg-1234');
		expect(formatResource(null, null)).toBe('—');
		expect(formatResource('channel', null)).toBe('channel');
	});

	it('truncateDetails', () => {
		expect(truncateDetails(null)).toBe('—');
		expect(truncateDetails('short')).toBe('short');
		expect(truncateDetails('x'.repeat(85)).endsWith('…')).toBe(true);
	});
});
