import { describe, expect, it } from 'vitest';
import {
	DEFAULT_RULE_PRIORITY,
	ROUTING_CHANNELS,
	buildCreateRuleBody,
	coercePriority,
	isChannel,
	isCreateRuleValid,
	parsePriorityInput,
	type RuleFormValues
} from './ruleForm';

function values(partial: Partial<RuleFormValues> = {}): RuleFormValues {
	return {
		owner_agent_id: 'owner-1',
		channel: 'discord',
		pattern: '^hello',
		target_agent_id: 'target-1',
		priority: DEFAULT_RULE_PRIORITY,
		...partial
	};
}

describe('isChannel', () => {
	it('accepts known channels only', () => {
		expect(isChannel('discord')).toBe(true);
		expect(isChannel('telegram')).toBe(true);
		expect(isChannel('email')).toBe(true);
		expect(isChannel('api')).toBe(true);
		expect(isChannel('sms')).toBe(false);
	});
});

describe('ROUTING_CHANNELS', () => {
	it('lists all four channels', () => {
		expect(ROUTING_CHANNELS).toEqual(['discord', 'telegram', 'email', 'api']);
	});
});

describe('isCreateRuleValid', () => {
	it('requires owner, target, and pattern', () => {
		expect(isCreateRuleValid(values())).toBe(true);
		expect(isCreateRuleValid(values({ owner_agent_id: '  ' }))).toBe(false);
		expect(isCreateRuleValid(values({ target_agent_id: '' }))).toBe(false);
		expect(isCreateRuleValid(values({ pattern: '   ' }))).toBe(false);
	});
});

describe('coercePriority', () => {
	it('accepts finite numbers and string inputs', () => {
		expect(coercePriority(4)).toBe(4);
		expect(coercePriority('9')).toBe(9);
		expect(coercePriority('bad')).toBe(DEFAULT_RULE_PRIORITY);
		expect(coercePriority(Number.NaN)).toBe(DEFAULT_RULE_PRIORITY);
	});
});

describe('buildCreateRuleBody', () => {
	it('returns null when invalid', () => {
		expect(buildCreateRuleBody(values({ pattern: '' }))).toBeNull();
	});

	it('omits default priority and includes non-default', () => {
		expect(buildCreateRuleBody(values())).toEqual({
			owner_agent_id: 'owner-1',
			channel: 'discord',
			pattern: '^hello',
			target_agent_id: 'target-1'
		});
		expect(buildCreateRuleBody(values({ priority: 10 }))).toEqual({
			owner_agent_id: 'owner-1',
			channel: 'discord',
			pattern: '^hello',
			target_agent_id: 'target-1',
			priority: 10
		});
		expect(buildCreateRuleBody(values({ priority: '12' }))?.priority).toBe(12);
	});

	it('trims string fields', () => {
		const body = buildCreateRuleBody(
			values({
				owner_agent_id: '  o1  ',
				pattern: '  ^x  ',
				target_agent_id: ' t1 '
			})
		);
		expect(body).toEqual({
			owner_agent_id: 'o1',
			channel: 'discord',
			pattern: '^x',
			target_agent_id: 't1'
		});
	});
});

describe('parsePriorityInput', () => {
	it('parses numbers and falls back on invalid', () => {
		expect(parsePriorityInput('7')).toBe(7);
		expect(parsePriorityInput('-3')).toBe(-3);
		expect(parsePriorityInput('')).toBe(DEFAULT_RULE_PRIORITY);
		expect(parsePriorityInput('nope')).toBe(DEFAULT_RULE_PRIORITY);
	});
});
