/** Pure helpers for Channels connectivity board grouping. */

import type { BossChannelConfig, Channel } from '$lib/api/types';

const CHANNEL_ORDER: readonly Channel[] = ['discord', 'telegram', 'email', 'api'] as const;

const BASE_KEYS = new Set([
	'id',
	'agent_id',
	'agent_name',
	'channel',
	'configured',
	'enabled',
	'created_at'
]);

export const CLI_NOTE =
	'Channel secrets are managed via the hiboss CLI — this view is read-only.';

export interface PublicField {
	key: string;
	value: string;
}

export interface AgentChannelGroup {
	agent_id: string;
	agent_name: string;
	channels: BossChannelConfig[];
}

export function channelOrderIndex(channel: string): number {
	const idx = (CHANNEL_ORDER as readonly string[]).indexOf(channel);
	return idx === -1 ? CHANNEL_ORDER.length : idx;
}

export function compareChannels(a: BossChannelConfig, b: BossChannelConfig): number {
	const byType = channelOrderIndex(a.channel) - channelOrderIndex(b.channel);
	if (byType !== 0) return byType;
	return a.id.localeCompare(b.id);
}

export function compareAgentGroups(a: AgentChannelGroup, b: AgentChannelGroup): number {
	const byName = a.agent_name.localeCompare(b.agent_name, undefined, { sensitivity: 'base' });
	if (byName !== 0) return byName;
	return a.agent_id.localeCompare(b.agent_id);
}

/** Non-secret config fields for display (excludes known base columns). */
export function publicFields(row: BossChannelConfig): PublicField[] {
	const fields: PublicField[] = [];
	for (const [key, raw] of Object.entries(row)) {
		if (BASE_KEYS.has(key)) continue;
		if (raw === null || raw === undefined) continue;
		fields.push({ key, value: String(raw) });
	}
	return fields.sort((a, b) => a.key.localeCompare(b.key));
}

export function configuredLabel(configured: boolean): string {
	return configured ? 'on' : 'off';
}

/** Group channel rows by agent; agents by name, channels by type order. */
export function groupChannelsByAgent(rows: BossChannelConfig[]): AgentChannelGroup[] {
	const map = new Map<string, AgentChannelGroup>();

	for (const row of rows) {
		const existing = map.get(row.agent_id);
		if (existing) {
			existing.channels.push(row);
			continue;
		}
		map.set(row.agent_id, {
			agent_id: row.agent_id,
			agent_name: row.agent_name,
			channels: [row]
		});
	}

	const groups = [...map.values()];
	for (const group of groups) {
		group.channels = [...group.channels].sort(compareChannels);
	}
	return groups.sort(compareAgentGroups);
}
