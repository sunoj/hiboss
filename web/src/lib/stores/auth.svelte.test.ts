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

describe('AuthStore.connect client exchange', () => {
	it('validates the pasted token then persists only the fresh browser token', async () => {
		const fetcher = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify({ id: 'boss-1', name: 'Boss', role: 'viewer' })))
			.mockResolvedValueOnce(new Response(JSON.stringify({ client: { id: 'browser-1' }, token: 'fresh-token' }), { status: 201 }));
		vi.stubGlobal('fetch', fetcher);
		await auth.connect('https://hiboss.test', 'shared-token');
		expect(fetcher.mock.calls[0][0]).toBe('https://hiboss.test/api/boss/me');
		expect(fetcher.mock.calls[1][0]).toBe('https://hiboss.test/api/boss/clients');
		expect(fetcher.mock.calls[1][1]).toMatchObject({ method: 'POST', headers: { Authorization: 'Bearer shared-token' } });
		expect(JSON.parse(fetcher.mock.calls[1][1].body as string)).toMatchObject({ kind: 'web', label: expect.any(String) });
		expect(loadConnection()?.token).toBe('fresh-token');
		expect(auth.client?.token).toBe('fresh-token');
		expect(auth.connection?.boss?.role).toBe('viewer');
	});

	it('does not store the pasted token when the exchange fails', async () => {
		vi.stubGlobal('fetch', vi.fn().mockResolvedValueOnce(new Response(JSON.stringify({ id: 'boss-1', name: 'Boss', role: 'admin' })))
			.mockResolvedValueOnce(new Response('exchange failed', { status: 503 })));
		await expect(auth.connect('https://hiboss.test', 'shared-token')).rejects.toThrow();
		expect(loadConnection()).toBeNull();
		expect(auth.isAuthenticated).toBe(false);
	});

	it('does not mint a client when paste-login validation fails', async () => {
		const fetcher = vi.fn().mockResolvedValue(new Response('Unauthorized', { status: 401 }));
		vi.stubGlobal('fetch', fetcher);
		await expect(auth.connect('https://hiboss.test', 'invalid-token')).rejects.toThrow();
		expect(fetcher).toHaveBeenCalledTimes(1);
		expect(loadConnection()).toBeNull();
	});
});
