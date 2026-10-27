// Verifies complete semantic guards and coercion boundaries with independent member literals.
// Depends on Vitest and the console semantic helpers.

import { expect, it } from 'vitest';
import {
	coercePriority,
	coerceSessionStatus,
	isDirection,
	isMessageStatus,
	isPriority,
	isSessionStatus
} from './semantics';

it.each([
	['priority', isPriority, ['critical', 'high', 'normal', 'low'], 'urgent'],
	['direction', isDirection, ['agent_to_boss', 'boss_to_agent', 'agent_to_agent'], 'boss_to_boss'],
	['message status', isMessageStatus, ['sent', 'delivered', 'read', 'replied', 'expired'], 'done'],
	['session status', isSessionStatus, ['working', 'waiting', 'blocked', 'completed', 'idle'], 'paused']
] as const)('%s accepts every member and rejects malformed values', (_name, guard, valid, other) => {
	const malformed = valid.flatMap(value => [` ${value}`, `${value} `, value.toUpperCase()]);
	for (const value of valid) {
		expect(guard(value)).toBe(true);
	}
	for (const value of ['', '__proto__', 'constructor', 'toString', other, ...malformed]) {
		expect(guard(value)).toBe(false);
	}
});

it.each([
	['priority', coercePriority, ['critical', 'high', 'normal', 'low'], 'normal'],
	['session status', coerceSessionStatus, ['working', 'waiting', 'blocked', 'completed', 'idle'], 'idle']
] as const)('%s coercion preserves members and defaults invalid input', (_name, coerce, valid, fallback) => {
	for (const value of valid) {
		expect(coerce(value)).toBe(value);
	}
	for (const value of [undefined, null, '', 'bogus', 'zombie', 'HIGH', 'working ', '__proto__']) {
		expect(coerce(value)).toBe(fallback);
	}
});
