// Checks the required-input membership and local closing rules.
// A history record alone must never enable an answer.

import { describe, expect, it } from 'vitest';
import { answerability } from './answerability';

describe('decision answerability', () => {
	const id = 'decision';
	const open = new Set([id]);
	const empty = new Set<string>();

	it('checks until a complete snapshot, including when an ID is already known', () => {
		expect(answerability(id, open, false, empty, null, 0)).toBe('checking');
		expect(answerability(id, empty, false, empty, null, 0)).toBe('checking');
	});

	it('requires membership in the loaded snapshot', () => {
		expect(answerability(id, open, true, empty, null, 0)).toBe('open');
		expect(answerability(id, empty, true, empty, null, 0)).toBe('closed');
	});

	it('closes withdrawn decisions and deadlines that have elapsed', () => {
		expect(answerability(id, open, false, open, null, 0)).toBe('closed');
		expect(answerability(id, open, true, empty, '1970-01-01T00:00:01Z', 1000)).toBe('closed');
	});
});
