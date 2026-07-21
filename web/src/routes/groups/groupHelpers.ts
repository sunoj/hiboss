/** Pure helpers for Groups list display and sorting. */

import type { GroupResponse } from '$lib/api/types';

/** Inline note shown next to disabled write affordances. */
export const WRITE_DISABLED_NOTE = 'needs a boss-scoped write endpoint';

export function compareGroupsByName(a: GroupResponse, b: GroupResponse): number {
	return a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
}

/** Stable copy sorted by name (case-insensitive). */
export function sortGroupsByName(groups: GroupResponse[]): GroupResponse[] {
	return [...groups].sort(compareGroupsByName);
}

export function memberCountLabel(count: number): string {
	if (count === 1) return '1 member';
	return `${count} members`;
}

/** Human-readable description, or a muted fallback when empty/null. */
export function displayDescription(description: string | null | undefined): string {
	const text = description?.trim();
	if (text) return text;
	return 'No description';
}

export function hasDescription(description: string | null | undefined): boolean {
	return Boolean(description?.trim());
}
