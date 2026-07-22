/** Connection persistence — boss token lives in localStorage only. */

import type { BossMe, ConnectionConfig } from './types';

export const DEFAULT_BASE_URL = '';

const STORAGE_KEY = 'hiboss.web.connection';

export interface StoredConnection extends ConnectionConfig {
	boss?: Pick<BossMe, 'id' | 'name' | 'role'>;
}

export function normalizeBaseUrl(url: string): string {
	return url.trim().replace(/\/+$/, '');
}

export function loadConnection(): StoredConnection | null {
	if (typeof localStorage === 'undefined') return null;
	try {
		const raw = localStorage.getItem(STORAGE_KEY);
		if (!raw) return null;
		const parsed = JSON.parse(raw) as Partial<StoredConnection>;
		if (!parsed.baseUrl || !parsed.token) return null;
		return {
			baseUrl: normalizeBaseUrl(parsed.baseUrl),
			token: String(parsed.token),
			boss: parsed.boss
		};
	} catch {
		return null;
	}
}

export function saveConnection(conn: StoredConnection): void {
	localStorage.setItem(STORAGE_KEY, JSON.stringify(conn));
}

export function clearConnection(): void {
	localStorage.removeItem(STORAGE_KEY);
}
