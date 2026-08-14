/** Pure helpers for Groups list display, sorting, and write UX copy. */

import type { AgentResponse, GroupResponse } from '$lib/api/types';
import { t } from '$lib/i18n';

export function compareGroupsByName(a: GroupResponse, b: GroupResponse): number {
	return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
}

/** Stable copy sorted by name (case-insensitive). */
export function sortGroupsByName(groups: GroupResponse[]): GroupResponse[] {
	return [...groups].sort(compareGroupsByName);
}

export function compareAgentsByName(a: AgentResponse, b: AgentResponse): number {
	return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
}

/** Stable copy of agents sorted by name. */
export function sortAgentsByName(agents: AgentResponse[]): AgentResponse[] {
	return [...agents].sort(compareAgentsByName);
}

export function memberCountLabel(count: number): string {
	return t('common.members', { count });
}

/** Human-readable description, or a muted fallback when empty/null. */
export function displayDescription(description: string | null | undefined): string {
	const text = description?.trim();
	if (text) return text;
	return t('form.noDescription');
}

export function hasDescription(description: string | null | undefined): boolean {
	return Boolean(description?.trim());
}

/** Whether create-group form fields are complete enough to submit. */
export function canCreateGroup(name: string, ownerAgentId: string): boolean {
	return Boolean(name.trim() && ownerAgentId.trim());
}

/** Select-option label: name plus short id for disambiguation. */
export function agentOptionLabel(agent: Pick<AgentResponse, 'id' | 'name'>): string {
	const short = agent.id.length > 8 ? agent.id.slice(0, 8) : agent.id;
	return `${agent.name} (${short})`;
}

/** Toast / status copy after a group broadcast. */
export function broadcastResultLabel(count: number): string {
	return t('form.broadcastDelivered', { count });
}

export function canSendBroadcast(groupId: string, body: string): boolean {
	return Boolean(groupId.trim() && body.trim());
}
