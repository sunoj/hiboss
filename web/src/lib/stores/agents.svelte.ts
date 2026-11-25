// Shares the scoped agent inventory across list, detail and message views.
// Replaces cached rows after a write and isolates each authenticated client.

import type { BossApiClient } from '$lib/api/client';
import type { AgentResponse } from '$lib/api/types';

class AgentDirectory {
	rows = $state<AgentResponse[]>([]);
	loaded = $state(false);
	private client: BossApiClient | null = null;
	private pending: Promise<void> | null = null;

	load(client: BossApiClient | null, force = false): Promise<void> {
		if (client !== this.client) {
			this.client = client;
			this.rows = [];
			this.loaded = false;
			this.pending = null;
		}
		if (!client) return Promise.resolve();
		if (this.pending) return this.pending;
		if (this.loaded && !force) return Promise.resolve();

		const request = client.agents().then(({ agents }) => {
			if (this.client !== client) return;
			this.rows = agents;
			this.loaded = true;
		}).finally(() => {
			if (this.pending === request) this.pending = null;
		});
		this.pending = request;
		return request;
	}

	update(client: BossApiClient, id: string, patch: Partial<AgentResponse>): void {
		if (this.client === client) this.rows = this.rows.map((row) => row.id === id ? { ...row, ...patch } : row);
	}
}

export const agentDirectory = new AgentDirectory();
