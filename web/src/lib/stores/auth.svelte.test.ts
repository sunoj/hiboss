// Tests token replacement in the reactive console auth store.
// Covers persisted and in-memory bearer updates after self-rotation.
// Depends on jsdom localStorage and the auth store.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { loadConnection, saveConnection } from '$lib/api';
import { auth } from './auth.svelte';

beforeEach(() => {
	const values = new Map<string, string>();
	vi.stubGlobal('localStorage', {
		getItem: (key: string) => values.get(key) ?? null,
		setItem: (key: string, value: string) => values.set(key, value),
		removeItem: (key: string) => values.delete(key)
	});
});

afterEach(() => {
	auth.signOut();
	vi.unstubAllGlobals();
});

describe('AuthStore.replaceToken', () => {
	it('replaces the persisted and active bearer token', () => {
		saveConnection({
			baseUrl: 'https://hiboss.test',
			token: 'old-token',
			boss: { id: 'boss-1', name: 'Boss', role: 'admin' }
		});
		auth.hydrate();

		auth.replaceToken('new-token');

		expect(auth.connection?.token).toBe('new-token');
		expect(auth.client?.token).toBe('new-token');
		expect(loadConnection()?.token).toBe('new-token');
	});
});
