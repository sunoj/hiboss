/** Named token helpers for priority / status / direction / session. */

import { t } from '$lib/i18n';

export type Priority = 'critical' | 'high' | 'normal' | 'low';
export type MessageStatus = 'sent' | 'delivered' | 'read' | 'replied' | 'expired';
export type Direction = 'agent_to_boss' | 'boss_to_agent' | 'agent_to_agent';
export type SessionStatus = 'working' | 'waiting' | 'blocked' | 'completed' | 'idle';

export const PRIORITIES: readonly Priority[] = ['critical', 'high', 'normal', 'low'] as const;

export const MESSAGE_STATUSES: readonly MessageStatus[] = [
	'sent',
	'delivered',
	'read',
	'replied',
	'expired'
] as const;

export const DIRECTIONS: readonly Direction[] = [
	'agent_to_boss',
	'boss_to_agent',
	'agent_to_agent'
] as const;

export const SESSION_STATUSES: readonly SessionStatus[] = [
	'working',
	'waiting',
	'blocked',
	'completed',
	'idle'
] as const;

const PRIORITY_VARS: Record<Priority, string> = {
	critical: 'var(--hb-priority-critical)',
	high: 'var(--hb-priority-high)',
	normal: 'var(--hb-priority-normal)',
	low: 'var(--hb-priority-low)'
};

const PRIORITY_BG_VARS: Record<Priority, string> = {
	critical: 'var(--hb-priority-critical-bg)',
	high: 'var(--hb-priority-high-bg)',
	normal: 'var(--hb-priority-normal-bg)',
	low: 'var(--hb-priority-low-bg)'
};

const STATUS_VARS: Record<MessageStatus, string> = {
	sent: 'var(--hb-status-sent)',
	delivered: 'var(--hb-status-delivered)',
	read: 'var(--hb-status-read)',
	replied: 'var(--hb-status-replied)',
	expired: 'var(--hb-status-expired)'
};

const DIRECTION_VARS: Record<Direction, string> = {
	agent_to_boss: 'var(--hb-dir-agent-to-boss)',
	boss_to_agent: 'var(--hb-dir-boss-to-agent)',
	agent_to_agent: 'var(--hb-dir-agent-to-agent)'
};

const SESSION_VARS: Record<SessionStatus, string> = {
	working: 'var(--hb-session-working)',
	waiting: 'var(--hb-session-waiting)',
	blocked: 'var(--hb-session-blocked)',
	completed: 'var(--hb-session-completed)',
	idle: 'var(--hb-session-idle)'
};

export function isPriority(value: string): value is Priority {
	return (PRIORITIES as readonly string[]).includes(value);
}

export function isMessageStatus(value: string): value is MessageStatus {
	return (MESSAGE_STATUSES as readonly string[]).includes(value);
}

export function isDirection(value: string): value is Direction {
	return (DIRECTIONS as readonly string[]).includes(value);
}

export function isSessionStatus(value: string): value is SessionStatus {
	return (SESSION_STATUSES as readonly string[]).includes(value);
}

export function priorityColor(priority: Priority): string {
	return PRIORITY_VARS[priority];
}

export function priorityBg(priority: Priority): string {
	return PRIORITY_BG_VARS[priority];
}

export function statusColor(status: MessageStatus): string {
	return STATUS_VARS[status];
}

export function directionColor(direction: Direction): string {
	return DIRECTION_VARS[direction];
}

export function sessionColor(status: SessionStatus): string {
	return SESSION_VARS[status];
}

export function directionLabel(direction: Direction): string {
	const key = direction === 'agent_to_boss' ? 'agentToBoss' : direction === 'boss_to_agent' ? 'bossToAgent' : 'agentToAgent';
	return t(`direction.${key}`);
}

export function priorityLabel(priority: Priority): string {
	return t(`priority.${priority}`);
}

export function statusLabel(status: MessageStatus): string {
	return t(`status.${status}`);
}

export function sessionLabel(status: SessionStatus): string {
	return t(`session.${status}`);
}

export function coercePriority(value: string | null | undefined): Priority {
	return value && isPriority(value) ? value : 'normal';
}

export function coerceSessionStatus(value: string | null | undefined): SessionStatus {
	return value && isSessionStatus(value) ? value : 'idle';
}
