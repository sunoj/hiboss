// Resumes the session stream at the last seen sequence and refreshes the HTTP snapshot.
// Depends on the console SSE reader and boss transport.

import type { BossApiClient } from '$lib/api/client';
import { readEventStream } from '$lib/api/event-stream';

export type StreamState = 'connecting' | 'online' | 'offline';

export async function watchTranscript(
	client: BossApiClient, id: string, signal: AbortSignal,
	setState: (state: StreamState) => void, refresh: () => void
): Promise<void> {
	let cursor: number | null = null;
	try { cursor = (await client.sessionEvents(id)).next_after ?? null; }
	catch { /* Start the stream without a cursor if event history is unavailable. */ }
	let delay = 3000;
	let timer: ReturnType<typeof setTimeout>;
	const base = client.baseUrl + '/api/sessions/' + encodeURIComponent(id) + '/stream';
	function scheduleRefresh() {
		clearTimeout(timer);
		timer = setTimeout(() => { if (!signal.aborted) refresh(); }, 200);
	}

	signal.addEventListener('abort', () => clearTimeout(timer), { once: true });
	while (!signal.aborted) {
		setState('connecting');
		try {
			const path = cursor === null ? base : base + '?after=' + cursor;
			await readEventStream(path, client.streamHeaders(), signal, (event, data) => {
				if (event === 'resync') cursor = null;
				if (event === 'session_event' && typeof data.sequence === 'number') {
					cursor = data.sequence;
					delay = 3000;
				}
				if (event === 'session_event' || event === 'resync') scheduleRefresh();
			}, () => {
				setState('online');
				scheduleRefresh();
			});
		} catch { /* The last transcript remains available during an interruption. */ }
		if (signal.aborted) return;
		setState('offline');
		await new Promise<void>((resolve) => setTimeout(resolve, delay));
		delay = Math.min(delay * 2, 30_000);
	}
}
