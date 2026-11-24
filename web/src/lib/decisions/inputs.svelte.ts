// Tracks the current boss's open decisions from the authenticated SSE stream.
// Only a complete snapshot makes the answer controls available.

import type { BossApiClient } from '$lib/api/client';
import { readEventStream } from '$lib/api/event-stream';
import { normalizeMessage } from '$lib/api/mappers';
import type { MessageResponse } from '$lib/api/types';

class Inputs {
	messages = $state<MessageResponse[]>([]);
	private ready = $state(false);
	private disconnectedAt = $state<number | null>(null);
	get loaded(): boolean {
		return this.ready && (this.disconnectedAt === null || this.now - this.disconnectedAt < 30_000);
	}
	connected = $state(false);
	settled = $state(new Set<string>());
	now = $state(Date.now());

	watch(client: BossApiClient): () => void {
		this.messages = [];
		this.ready = false;
		this.disconnectedAt = null;
		this.connected = false;
		this.settled = new Set();
		const stop = new AbortController();
		const interval = setInterval(() => { this.now = Date.now(); }, 1000);
		void this.reconnect(client, stop.signal);
		return () => {
			stop.abort();
			clearInterval(interval);
		};
	}

	close(id: string): void {
		this.settled = new Set([...this.settled, id]);
	}

	private async reconnect(client: BossApiClient, signal: AbortSignal): Promise<void> {
		while (!signal.aborted) {
			try { await this.stream(client, signal); } catch { /* Keep the last complete snapshot. */ }
			if (signal.aborted) return;
			if (this.connected) this.disconnectedAt = Date.now();
			this.connected = false;
			await new Promise<void>((resolve) => setTimeout(resolve, 3000));
		}
	}

	private async stream(client: BossApiClient, signal: AbortSignal): Promise<void> {
		const snapshot = new Map<string, MessageResponse>();
		let ready = false;
		await readEventStream(client.streamUrl('inputs'), client.streamHeaders(), signal, (event, data) => {
			if (event === 'message' && typeof data.id === 'string') {
				snapshot.set(data.id, normalizeMessage(data));
			} else if (event === 'resolved' && typeof data.id === 'string') {
				snapshot.delete(data.id);
				this.close(data.id);
			} else if (event === 'ready') {
				ready = true;
				this.ready = true;
				this.disconnectedAt = null;
				this.connected = true;
			}
			if (ready) this.messages = [...snapshot.values()];
		});
	}
}

export const inputs = new Inputs();
