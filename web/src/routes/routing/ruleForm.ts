/** Pure helpers for Routing rule create form. */

import type { Channel, CreateRoutingRuleRequest } from '$lib/api/types';

export const ROUTING_CHANNELS: readonly Channel[] = [
	'discord',
	'telegram',
	'email',
	'api'
] as const;

export const DEFAULT_RULE_PRIORITY = 0;

export interface RuleFormValues {
	owner_agent_id: string;
	channel: Channel;
	pattern: string;
	target_agent_id: string;
	priority: number | string;
}

export function isChannel(value: string): value is Channel {
	return (ROUTING_CHANNELS as readonly string[]).includes(value);
}

export function parsePriorityInput(raw: string): number {
	const n = Number(raw);
	return Number.isFinite(n) ? n : DEFAULT_RULE_PRIORITY;
}

/** Coerce number-input bindings (may be string) to a finite priority. */
export function coercePriority(value: number | string): number {
	if (typeof value === 'number' && Number.isFinite(value)) return value;
	return parsePriorityInput(String(value));
}

/** True when required fields are present. */
export function isCreateRuleValid(values: RuleFormValues): boolean {
	return (
		values.owner_agent_id.trim().length > 0 &&
		values.target_agent_id.trim().length > 0 &&
		values.pattern.trim().length > 0 &&
		isChannel(values.channel)
	);
}

/** Build API body; omits priority when it matches the server default. */
export function buildCreateRuleBody(values: RuleFormValues): CreateRoutingRuleRequest | null {
	if (!isCreateRuleValid(values)) return null;
	const priority = coercePriority(values.priority);
	const body: CreateRoutingRuleRequest = {
		owner_agent_id: values.owner_agent_id.trim(),
		channel: values.channel,
		pattern: values.pattern.trim(),
		target_agent_id: values.target_agent_id.trim()
	};
	if (priority !== DEFAULT_RULE_PRIORITY) {
		body.priority = priority;
	}
	return body;
}
