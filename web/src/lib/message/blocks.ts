// Message Markdown block parser with opt-in server embed decoding.
// Parsing produces typed data only, with no HTML output.

import { decodeEmbed, type Embed } from './embed';

export type Block = { kind: 'paragraph' | 'heading' | 'quote' | 'code'; text: string }
	| { kind: 'list'; ordered: boolean; items: string[] }
	| { kind: 'copy'; text: string; label: string }
	| { kind: 'embed'; card: Embed };

export function displayContent(metadata?: Record<string, unknown> | null):
	{ text: string; embeds: boolean } {
	if (typeof metadata?.rich_content === 'string') return { text: metadata.rich_content, embeds: true };
	return { text: typeof metadata?.content === 'string' ? metadata.content : '', embeds: false };
}

const fence = /^ {0,3}(`{3,}|~{3,})(.*)$/;
const heading = /^ {0,3}#{1,6}\s+(.+?)\s*#*$/;
const quote = /^ {0,3}> ?(.*)$/;
const item = /^(?:([-+*])|(\d+[.)]))\s+(.*)$/;
const tableDelimiter = /^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$/;

function fencedBlock(lines: string[], start: number, opening: RegExpMatchArray, embeds: boolean) {
	const marker = opening[1];
	const closing = new RegExp('^ {0,3}' + marker[0] + '{' + marker.length + ',}\\s*$');
	let end = start + 1;
	while (end < lines.length && !closing.test(lines[end])) end++;
	const text = lines.slice(start + 1, end).join('\n');
	const info = opening[2].trim();
	let block: Block = { kind: 'code', text };
	if (end < lines.length) {
		const copy = info.match(/^copy(?:\s+(.*))?$/);
		const card = embeds && info === 'hiboss-embed' ? decodeEmbed(text) : undefined;
		if (copy) block = { kind: 'copy', label: copy[1] ?? '', text };
		else if (card) block = { kind: 'embed', card };
	}
	return { block, next: end + 1 };
}

function runOfLines(lines: string[], start: number, pattern: RegExp) {
	let end = start;
	const matches: RegExpMatchArray[] = [];
	for (; end < lines.length; end++) {
		const match = lines[end].match(pattern);
		if (!match) break;
		matches.push(match);
	}
	return { matches, end };
}

export function parseBlocks(source: string, embeds = false): Block[] {
	const lines = source.replace(/\r\n?/g, '\n').split('\n');
	const blocks: Block[] = [];
	let i = 0;
	while (i < lines.length) {
		const line = lines[i];
		const opening = line.match(fence);
		const title = line.match(heading);
		if (!line.trim()) i++;
		else if (opening) {
			const { block, next } = fencedBlock(lines, i, opening, embeds);
			blocks.push(block);
			i = next;
		} else if (title) {
			blocks.push({ kind: 'heading', text: title[1] });
			i++;
		} else if (quote.test(line)) {
			const { matches, end } = runOfLines(lines, i, quote);
			blocks.push({ kind: 'quote', text: matches.map((match) => match[1]).join('\n') });
			i = end;
		} else if (item.test(line)) {
			const ordered = /^\d/.test(line);
			const pattern = ordered ? /^(\d+[.)])\s+(.*)$/ : /^([-+*])\s+(.*)$/;
			const { matches, end } = runOfLines(lines, i, pattern);
			blocks.push({ kind: 'list', ordered, items: matches.map((match) => match[2]) });
			i = end;
		} else {
			let end = i + 1;
			if (line.includes('|') && tableDelimiter.test(lines[end] ?? '')) {
				end++;
				while (lines[end]?.includes('|')) end++;
				blocks.push({ kind: 'paragraph', text: lines.slice(i, end).join('\n') });
			} else {
				while (lines[end]?.trim() && ![fence, heading, quote, item].some((rule) => rule.test(lines[end]))) end++;
				blocks.push({ kind: 'paragraph', text: lines.slice(i, end).join('\n') });
			}
			i = end;
		}
	}
	return blocks;
}
