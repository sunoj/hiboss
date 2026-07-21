/** Pure helpers for Bosses & Access matrix and bindings. */

import type { BossRecord, BossRole } from '$lib/api/types';

export function hasAccess(boss: BossRecord, agentId: string): boolean {
	const ids = boss.agent_ids ?? [];
	return ids.includes(agentId);
}

/** Return a new bosses array with agentId granted or revoked on the matching boss. */
export function withAccess(
	bosses: BossRecord[],
	bossId: string,
	agentId: string,
	granted: boolean
): BossRecord[] {
	return bosses.map((boss) => {
		if (boss.id !== bossId) return boss;
		const current = boss.agent_ids ?? [];
		const next = granted
			? current.includes(agentId)
				? current
				: [...current, agentId]
			: current.filter((id) => id !== agentId);
		return { ...boss, agent_ids: next };
	});
}

export function roleLabel(role: BossRole | string): string {
	switch (role) {
		case 'admin':
			return 'Admin';
		case 'manager':
			return 'Manager';
		case 'viewer':
			return 'Viewer';
		default:
			return String(role);
	}
}

/** CSS tone class key for role badges — maps to semantic vars in markup. */
export type RoleTone = 'admin' | 'manager' | 'viewer' | 'unknown';

export function roleTone(role: BossRole | string): RoleTone {
	if (role === 'admin' || role === 'manager' || role === 'viewer') return role;
	return 'unknown';
}

export function formatBinding(id: string | null | undefined): string {
	const v = id?.trim();
	if (!v) return '—';
	return v;
}

export function bindingSummary(boss: BossRecord): { telegram: string; discord: string } {
	return {
		telegram: formatBinding(boss.telegram_user_id),
		discord: formatBinding(boss.discord_user_id)
	};
}

export function shortId(id: string, max = 8): string {
	if (id.length <= max) return id;
	return id.slice(0, max);
}

export const BOSS_ROLES: BossRole[] = ['admin', 'manager', 'viewer'];
