// Reads event and JSON data frames from authenticated console streams.
// Both server streams send one JSON value on each data line.

export async function readEventStream(
	url: string, headers: HeadersInit, signal: AbortSignal,
	onEvent: (event: string, data: Record<string, unknown>) => void
): Promise<boolean> {
	const response = await fetch(url, { headers, signal });
	if (!response.ok || !response.body || !response.headers.get('content-type')?.includes('text/event-stream')) {
		return false;
	}
	const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
	let buffer = '';
	try {
		while (!signal.aborted) {
			const { value, done } = await reader.read();
			if (done || signal.aborted) break;
			buffer += value;
			const frames = buffer.split(/\r?\n\r?\n/);
			buffer = frames.pop() ?? '';
			for (const frame of frames) {
				const event = frame.match(/^event: (.+)$/m)?.[1]?.trim();
				const json = frame.match(/^data: (.+)$/m)?.[1];
				if (event && json) onEvent(event, JSON.parse(json) as Record<string, unknown>);
			}
		}
		return true;
	} finally {
		await reader.cancel().catch(() => undefined);
	}
}
