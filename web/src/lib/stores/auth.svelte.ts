/** Reactive auth / connection state for the SPA. */

import {
	BossApiClient,
	clearConnection,
	loadConnection,
	saveConnection,
	validateConnection,
	type StoredConnection
} from '$lib/api';

class AuthStore {
	connection = $state<StoredConnection | null>(null);
	ready = $state(false);
	client = $state<BossApiClient | null>(null);

	hydrate(): void {
		const stored = loadConnection();
		this.connection = stored;
		this.client = stored ? BossApiClient.fromConnection(stored) : null;
		this.ready = true;
	}

	get isAuthenticated(): boolean {
		return this.connection != null && this.client != null;
	}

	async connect(baseUrl: string, token: string): Promise<void> {
		const boss = await validateConnection(baseUrl, token);
		const stored: StoredConnection = {
			baseUrl,
			token,
			boss: { id: boss.id, name: boss.name, role: boss.role }
		};
		saveConnection(stored);
		this.connection = stored;
		this.client = BossApiClient.fromConnection(stored);
	}

	replaceToken(token: string): void {
		if (!this.connection) return;
		const stored: StoredConnection = { ...this.connection, token };
		saveConnection(stored);
		this.connection = stored;
		this.client = BossApiClient.fromConnection(stored);
	}

	signOut(): void {
		clearConnection();
		this.connection = null;
		this.client = null;
	}
}

export const auth = new AuthStore();
