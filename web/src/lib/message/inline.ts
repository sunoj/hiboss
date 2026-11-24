// Safe inline Markdown tokens and URL boundaries.
// Used by message headings, prose, and embed text.

export type Inline = { kind: 'text' | 'code' | 'strong' | 'em'; text: string }
	| { kind: 'link'; text: string; href: string };

export function safeLink(value: unknown): string | undefined {
	return typeof value === 'string' && /^(https?:\/\/|mailto:)[^\s\x00-\x1f]+$/i.test(value)
		? value : undefined;
}

function trimBare(url: string): string {
	let end = url.length;
	const excess = (open: string, close: string) =>
		url.slice(0, end).split(close).length > url.slice(0, end).split(open).length;
	while (end > 0) {
		const last = url[end - 1];
		if (/[.,;:!?'"]/.test(last) || (last === ')' && excess('(', ')'))
			|| (last === ']' && excess('[', ']'))) end--;
		else break;
	}
	return url.slice(0, end);
}

export function parseInline(text: string, markdown = true): Inline[] {
	const pattern = markdown
		? /(`+)([^\n]+?)\1|!?\[([^\]\n]+)\]\(((?:[^()\s]|\([^()\s]*\))+)\)|(\*\*|__|\*|_)([^\n]+?)\5|https?:\/\/[!-~]+/gi
		: /https?:\/\/[!-~]+/gi;
	const result: Inline[] = [];
	let offset = 0;
	for (const match of text.matchAll(pattern)) {
		const raw = match[0];
		const index = match.index ?? 0;
		if (index > offset) result.push({ kind: 'text', text: text.slice(offset, index) });
		offset = index + raw.length;
		if (match[1]) result.push({ kind: 'code', text: match[2] });
		else if (match[3]) {
			const href = !raw.startsWith('!') && safeLink(match[4]);
			result.push(href ? { kind: 'link', text: match[3], href } : { kind: 'text', text: raw });
		} else if (match[5]) result.push({ kind: match[5].length === 2 ? 'strong' : 'em', text: match[6] });
		else {
			const href = trimBare(raw);
			if (safeLink(href)) result.push({ kind: 'link', text: href, href });
			else result.push({ kind: 'text', text: href });
			offset = index + href.length;
		}
	}
	if (offset < text.length) result.push({ kind: 'text', text: text.slice(offset) });
	return result;
}
