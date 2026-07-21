import { describe, expect, it } from 'vitest';
import type { BossRecord } from '$lib/api/types';
import {
	bindingSummary,
	formatBinding,
	hasAccess,
	roleLabel,
	roleTone,
	shortId,
	withAccess
} from './access-helpers';

function boss(partial: Partial<BossRecord> & Pick<BossRecord, 'id'>): BossRecord {
	return {
		name: 'Boss',
		role: 'manager',
		telegram_user_id: null,
		discord_user_id: null,
		agent_id: null,
		preferences: null,
		created_at: '2026-07-21T00:00:00Z',
		agent_ids: [],
		...partial
	};
}

describe('hasAccess', () => {
	it('checks agent_ids membership', () => {
		expect(hasAccess(boss({ id: 'b1', agent_ids: ['a1', 'a2'] }), 'a1')).toBe(true);
		expect(hasAccess(boss({ id: 'b1', agent_ids: ['a1'] }), 'a9')).toBe(false);
		expect(hasAccess(boss({ id: 'b1' }), 'a1')).toBe(false);
	});
});

describe('withAccess', () => {
	it('grants and revokes without mutating other bosses', () => {
		const bosses = [
			boss({ id: 'b1', agent_ids: ['a1'] }),
			boss({ id: 'b2', agent_ids: ['a1'] })
		];
		const granted = withAccess(bosses, 'b1', 'a2', true);
		expect(granted[0].agent_ids).toEqual(['a1', 'a2']);
		expect(granted[1].agent_ids).toEqual(['a1']);
		expect(bosses[0].agent_ids).toEqual(['a1']);

		const revoked = withAccess(granted, 'b1', 'a1', false);
		expect(revoked[0].agent_ids).toEqual(['a2']);
	});

	it('is idempotent on grant', () => {
		const bosses = [boss({ id: 'b1', agent_ids: ['a1'] })];
		expect(withAccess(bosses, 'b1', 'a1', true)[0].agent_ids).toEqual(['a1']);
	});
});

describe('role helpers', () => {
	it('labels and tones known roles', () => {
		expect(roleLabel('admin')).toBe('Admin');
		expect(roleLabel('manager')).toBe('Manager');
		expect(roleLabel('viewer')).toBe('Viewer');
		expect(roleLabel('custom')).toBe('custom');
		expect(roleTone('admin')).toBe('admin');
		expect(roleTone('weird')).toBe('unknown');
	});
});

describe('bindings', () => {
	it('formats empty and present ids', () => {
		expect(formatBinding(null)).toBe('—');
		expect(formatBinding('  ')).toBe('—');
		expect(formatBinding('12345')).toBe('12345');
		expect(bindingSummary(boss({ id: 'b', telegram_user_id: 'tg1', discord_user_id: null }))).toEqual({
			telegram: 'tg1',
			discord: '—'
		});
	});
});

describe('shortId', () => {
	it('truncates long ids', () => {
		expect(shortId('abcdefghijklmnop')).toBe('abcdefgh');
		expect(shortId('abc')).toBe('abc');
	});
});
