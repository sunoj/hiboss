import { describe, expect, it } from 'vitest';
import {
	coercePriority,
	coerceSessionStatus,
	isDirection,
	isMessageStatus,
	isPriority,
	isSessionStatus
} from './semantics';

describe('type guards', () => {
	it('accepts valid enum members and rejects others', () => {
		expect(isPriority('critical')).toBe(true);
		expect(isPriority('urgent')).toBe(false);
		expect(isDirection('agent_to_agent')).toBe(true);
		expect(isDirection('boss_to_boss')).toBe(false);
		expect(isMessageStatus('replied')).toBe(true);
		expect(isMessageStatus('done')).toBe(false);
		expect(isSessionStatus('blocked')).toBe(true);
		expect(isSessionStatus('paused')).toBe(false);
	});
});

describe('coercion', () => {
	it('coercePriority falls back to normal for missing/invalid input', () => {
		expect(coercePriority('high')).toBe('high');
		expect(coercePriority(undefined)).toBe('normal');
		expect(coercePriority('bogus')).toBe('normal');
	});

	it('coerceSessionStatus falls back to idle for missing/invalid input', () => {
		expect(coerceSessionStatus('working')).toBe('working');
		expect(coerceSessionStatus(null)).toBe('idle');
		expect(coerceSessionStatus('zombie')).toBe('idle');
	});
});
