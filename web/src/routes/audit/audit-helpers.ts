/** Pure helpers for Audit module filters, query building, and pagination. */

import type { AuditActorType, AuditEntry, AuditQuery } from '$lib/api/types';
import { t } from '$lib/i18n';

export type ActorTypeFilter = 'all' | AuditActorType;

export interface AuditFilterState {
	actor_type: ActorTypeFilter;
	action: string;
	search: string;
	limit: number;
	offset: number;
}

export const ACTOR_TYPES: readonly AuditActorType[] = ['boss', 'agent', 'system'] as const;

export const COMMON_ACTIONS: readonly string[] = [
	'message.send',
	'message.reply',
	'message.forward',
	'message.edit',
	'channel.set',
	'agent.config',
	'boss.create',
	'boss.update',
	'boss.delete',
	'boss.grant',
	'boss.revoke',
	'boss.token',
	'boss.preferences',
	'join.approve',
	'join.reject',
	'join_request.create',
	'join_request.approve',
	'join_request.reject'
] as const;

export const PAGE_SIZE_OPTIONS = [25, 50, 100, 200] as const;
export const DEFAULT_LIMIT = 50;
export const MAX_LIMIT = 200;

export const DEFAULT_FILTERS: AuditFilterState = {
	actor_type: 'all',
	action: '',
	search: '',
	limit: DEFAULT_LIMIT,
	offset: 0
};

export function clampLimit(limit: number): number {
	if (!Number.isFinite(limit) || limit < 1) return DEFAULT_LIMIT;
	return Math.min(Math.floor(limit), MAX_LIMIT);
}

export function clampOffset(offset: number): number {
	if (!Number.isFinite(offset) || offset < 0) return 0;
	return Math.floor(offset);
}

/** Map UI filters to boss API query params. */
export function buildAuditQuery(filters: AuditFilterState): AuditQuery {
	const query: AuditQuery = {
		limit: clampLimit(filters.limit),
		offset: clampOffset(filters.offset)
	};
	if (filters.actor_type !== 'all') query.actor_type = filters.actor_type;
	const action = filters.action.trim();
	if (action) query.action = action;
	return query;
}

/** Client-side text filter across action / actor / resource / details. */
export function applyLocalSearch(entries: AuditEntry[], search: string): AuditEntry[] {
	const q = search.trim().toLowerCase();
	if (!q) return entries;
	return entries.filter((e) => entryMatchesSearch(e, q));
}

function entryMatchesSearch(entry: AuditEntry, q: string): boolean {
	const haystacks = [
		entry.action,
		entry.actor_type,
		entry.actor_id,
		entry.resource_type ?? '',
		entry.resource_id ?? '',
		entry.details ?? '',
		entry.id
	];
	return haystacks.some((h) => h.toLowerCase().includes(q));
}

export function canGoPrev(offset: number): boolean {
	return clampOffset(offset) > 0;
}

export function canGoNext(offset: number, limit: number, total: number): boolean {
	const off = clampOffset(offset);
	const lim = clampLimit(limit);
	return off + lim < total;
}

export function prevOffset(offset: number, limit: number): number {
	return Math.max(0, clampOffset(offset) - clampLimit(limit));
}

export function nextOffset(offset: number, limit: number): number {
	return clampOffset(offset) + clampLimit(limit);
}

/** 1-based inclusive range for pager label, e.g. "1–50 of 120". */
export function pageRange(
	offset: number,
	limit: number,
	total: number,
	visibleCount: number
): { from: number; to: number; total: number } {
	if (total <= 0 || visibleCount <= 0) return { from: 0, to: 0, total };
	const from = clampOffset(offset) + 1;
	const to = Math.min(clampOffset(offset) + visibleCount, total);
	return { from, to, total };
}

export function formatPageLabel(
	offset: number,
	limit: number,
	total: number,
	visibleCount: number
): string {
	const { from, to } = pageRange(offset, limit, total, visibleCount);
	if (total === 0) return t('pager.empty');
	return t('pager.range', { from, to, total });
}

export function actorTypeLabel(type: AuditActorType): string {
	switch (type) {
		case 'boss':
			return t('nav.bosses');
		case 'agent':
			return t('nav.agents');
		case 'system':
			return t('nav.system');
	}
}

export function formatResource(type: string | null, id: string | null): string {
	const t = type?.trim();
	const i = id?.trim();
	if (t && i) return `${t}:${shortId(i)}`;
	if (t) return t;
	if (i) return shortId(i);
	return '—';
}

export function shortId(id: string, len = 8): string {
	return id.length <= len ? id : id.slice(0, len);
}

export function truncateDetails(details: string | null, max = 80): string {
	if (!details) return '—';
	const trimmed = details.trim();
	if (!trimmed) return '—';
	return trimmed.length <= max ? trimmed : `${trimmed.slice(0, max)}…`;
}

export function resetOffset(filters: AuditFilterState): AuditFilterState {
	return { ...filters, offset: 0 };
}
