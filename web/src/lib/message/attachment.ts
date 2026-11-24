// Attachment metadata and bounded UTF-8 reads for Markdown previews.
// Public attachment URLs can be opened directly from the application.

export function attachmentName(url: string): string {
	try {
		const component = new URL(url).pathname.split('/').filter(Boolean).at(-1);
		return component ? decodeURIComponent(component) : '';
	} catch { return ''; }
}

export function attachmentKind(name: string): 'image' | 'markdown' | 'file' {
	if (/\.(avif|gif|jpe?g|png|webp)$/i.test(name)) return 'image';
	if (/\.(md|markdown)$/i.test(name)) return 'markdown';
	return 'file';
}

export async function readMarkdown(response: Response): Promise<string> {
	const max = 2 * 1024 * 1024;
	if (!response.ok || !response.body || Number(response.headers.get('content-length')) > max) {
		throw new Error('Invalid attachment');
	}
	const reader = response.body.getReader();
	const decoder = new TextDecoder('utf-8', { fatal: true });
	let text = '';
	let length = 0;
	try {
		for (;;) {
			const { value, done } = await reader.read();
			if (done) return text + decoder.decode();
			length += value.byteLength;
			if (length > max) throw new Error('Attachment exceeds preview limit');
			text += decoder.decode(value, { stream: true });
		}
	} finally {
		await reader.cancel().catch(() => undefined);
	}
}
