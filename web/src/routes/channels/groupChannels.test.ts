import { describe, expect, it } from 'vitest';
import type { BossChannelConfig } from '$lib/api/types';
import {
	channelOrderIndex,
	compareChannels,
	configuredLabel,
	groupChannelsByAgent,
	publicFields
} from './groupChannels';

function row(
	partial: Partial<BossChannelConfig> &
		Pick<BossChannelConfig, 'id' | 'agent_id' | 'agent_name' | 'channel'>
): BossChannelConfig {
	return {
		configured: true,
		enabled: 1,
		created_at: '2026-07-01T00:00:00Z',
		...partial
	};
}

describe('channelOrderIndex', () => {
	it('orders known channels and puts unknowns last', () => {
		expect(channelOrderIndex('discord')).toBe(0);
		expect(channelOrderIndex('telegram')).toBe(1);
		expect(channelOrderIndex('email')).toBe(2);
		expect(channelOrderIndex('api')).toBe(3);
		expect(channelOrderIndex('unknown')).toBe(4);
	});
});

describe('compareChannels', () => {
	it('sorts by channel type then id', () => {
		const a = row({ id: 'b', agent_id: '1', agent_name: 'A', channel: 'telegram' });
		const b = row({ id: 'a', agent_id: '1', agent_name: 'A', channel: 'discord' });
		const c = row({ id: 'c', agent_id: '1', agent_name: 'A', channel: 'discord' });
		expect(compareChannels(b, a)).toBeLessThan(0);
		expect(compareChannels(b, c)).toBeLessThan(0);
	});
});

describe('publicFields', () => {
	it('omits base columns and formats values', () => {
		const cfg = row({
			id: '1',
			agent_id: 'a',
			agent_name: 'Agent',
			channel: 'discord',
			channel_id: '123',
			quiet_start: '22:00',
			bot_token: null
		});
		expect(publicFields(cfg)).toEqual([
			{ key: 'channel_id', value: '123' },
			{ key: 'quiet_start', value: '22:00' }
		]);
	});
});

describe('configuredLabel', () => {
	it('maps boolean to on/off', () => {
		expect(configuredLabel(true)).toBe('on');
		expect(configuredLabel(false)).toBe('off');
	});
});

describe('groupChannelsByAgent', () => {
	it('groups by agent, sorts agents by name and channels by type', () => {
		const rows = [
			row({ id: '1', agent_id: 'z', agent_name: 'Zed', channel: 'api' }),
			row({ id: '2', agent_id: 'a', agent_name: 'Ann', channel: 'telegram' }),
			row({ id: '3', agent_id: 'a', agent_name: 'Ann', channel: 'discord' }),
			row({ id: '4', agent_id: 'z', agent_name: 'Zed', channel: 'discord' })
		];

		const groups = groupChannelsByAgent(rows);
		expect(groups.map((g) => g.agent_name)).toEqual(['Ann', 'Zed']);
		expect(groups[0].channels.map((c) => c.channel)).toEqual(['discord', 'telegram']);
		expect(groups[1].channels.map((c) => c.channel)).toEqual(['discord', 'api']);
	});

	it('returns empty array for empty input', () => {
		expect(groupChannelsByAgent([])).toEqual([]);
	});
});
