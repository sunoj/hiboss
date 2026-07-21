import { describe, expect, it } from 'vitest';
import type { ChannelHealth } from '$lib/api/types';
import {
	channelHealthHint,
	channelStats,
	emptyConnectivity,
	formatLatency,
	formatServerTime,
	healthDetail,
	healthLabel,
	overallHealth
} from './doctor-helpers';

describe('overallHealth', () => {
	it('returns ok only when both probes pass', () => {
		expect(overallHealth(true, true)).toBe('ok');
		expect(overallHealth(true, false)).toBe('degraded');
		expect(overallHealth(false, true)).toBe('degraded');
		expect(overallHealth(false, false)).toBe('fail');
	});
});

describe('healthLabel / healthDetail', () => {
	it('labels tones', () => {
		expect(healthLabel('ok')).toBe('Healthy');
		expect(healthLabel('degraded')).toBe('Degraded');
		expect(healthLabel('fail')).toBe('Unhealthy');
	});

	it('summarizes probe pair', () => {
		expect(healthDetail(true, true)).toBe('DB ok · API ok');
		expect(healthDetail(false, true)).toBe('DB fail · API ok');
	});
});

describe('formatLatency', () => {
	it('formats ms and seconds', () => {
		expect(formatLatency(42)).toBe('42 ms');
		expect(formatLatency(1500)).toBe('1.5 s');
		expect(formatLatency(null)).toBe('—');
		expect(formatLatency(-1)).toBe('—');
	});
});

describe('formatServerTime', () => {
	it('formats valid ISO and guards invalid', () => {
		expect(formatServerTime('2026-07-21T12:34:56.789Z')).toBe('2026-07-21 12:34:56 UTC');
		expect(formatServerTime('not-a-date')).toBe('—');
	});
});

describe('channelStats / channelHealthHint', () => {
	const channels: ChannelHealth[] = [
		{ channel: 'discord', configured: true },
		{ channel: 'telegram', configured: false },
		{ channel: 'email', configured: true }
	];

	it('counts configured channels', () => {
		expect(channelStats(channels)).toEqual({ configured: 2, total: 3 });
		expect(channelStats([])).toEqual({ configured: 0, total: 0 });
	});

	it('builds hint text', () => {
		expect(channelHealthHint(channels)).toBe('2/3 configured');
		expect(channelHealthHint([])).toBe('No channels reported');
	});
});

describe('emptyConnectivity', () => {
	it('returns a failed empty probe shell', () => {
		expect(emptyConnectivity()).toEqual({
			ok: false,
			latencyMs: null,
			bossName: null,
			bossRole: null,
			error: null
		});
	});
});
