/** Pure helpers for the System / Doctor connectivity dashboard. */

import type { ChannelHealth } from '$lib/api/types';

export type HealthTone = 'ok' | 'degraded' | 'fail';

export interface ConnectivityResult {
	ok: boolean;
	latencyMs: number | null;
	bossName: string | null;
	bossRole: string | null;
	error: string | null;
}

/** Combined DB + live me() probe into a single traffic-light tone. */
export function overallHealth(dbOk: boolean, meOk: boolean): HealthTone {
	if (dbOk && meOk) return 'ok';
	if (dbOk || meOk) return 'degraded';
	return 'fail';
}

export function healthLabel(tone: HealthTone): string {
	switch (tone) {
		case 'ok':
			return 'Healthy';
		case 'degraded':
			return 'Degraded';
		case 'fail':
			return 'Unhealthy';
	}
}

export function healthDetail(dbOk: boolean, meOk: boolean): string {
	const db = dbOk ? 'DB ok' : 'DB fail';
	const api = meOk ? 'API ok' : 'API fail';
	return `${db} · ${api}`;
}

export function formatLatency(ms: number | null): string {
	if (ms == null || !Number.isFinite(ms) || ms < 0) return '—';
	const rounded = Math.round(ms);
	if (rounded < 1000) return `${rounded} ms`;
	return `${(rounded / 1000).toFixed(1)} s`;
}

/** Human-readable UTC server clock from an ISO timestamp. */
export function formatServerTime(iso: string): string {
	const ms = Date.parse(iso);
	if (Number.isNaN(ms)) return '—';
	return new Date(ms).toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, ' UTC');
}

export function channelStats(channels: ChannelHealth[]): {
	configured: number;
	total: number;
} {
	const total = channels.length;
	const configured = channels.filter((c) => c.configured).length;
	return { configured, total };
}

export function channelHealthHint(channels: ChannelHealth[]): string {
	const { configured, total } = channelStats(channels);
	if (total === 0) return 'No channels reported';
	return `${configured}/${total} configured`;
}

export function emptyConnectivity(): ConnectivityResult {
	return {
		ok: false,
		latencyMs: null,
		bossName: null,
		bossRole: null,
		error: null
	};
}
