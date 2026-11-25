// Verifies exact English countdown copy and the two announcement thresholds.
// The timer can skip ticks when a browser tab is in the background.
import { expect, it } from 'vitest';
import { crossedThreshold, remainingTime } from './timing';

it('formats English abbreviations without punctuation', () => {
	expect(remainingTime(1071, 'en')).toBe('18 min');
	expect(remainingTime(59, 'en')).toBe('59 sec');
});

it('announces crossings and skips ordinary ticks and already-passed deadlines', () => {
	expect(crossedThreshold(301, 300)).toBe(300);
	expect(crossedThreshold(300, 299)).toBeUndefined();
	expect(crossedThreshold(62, 59)).toBe(60);
	expect(crossedThreshold(60, 59)).toBeUndefined();
	expect(crossedThreshold(62, 0)).toBeUndefined();
	expect(crossedThreshold(0, 50)).toBeUndefined();
});
