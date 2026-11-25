// Regression coverage for safe message parsing and native-format parity.
// Tests the same typed tokens that the Svelte renderer consumes.

import { describe, expect, it } from 'vitest';
import { displayContent, parseBlocks } from './blocks';
import { parseInline } from './inline';

const embed = (value: object) => '```hiboss-embed\n' + JSON.stringify(value) + '\n```';

describe('message renderer', () => {
	it('recognizes supported blocks and leaves unsupported markup as text', () => {
		expect(parseBlocks('# Head\n\nHello **world**\n\n> Quote\n\n- Item\n\n1. First\n\n<img>'))
			.toEqual([
				{ kind: 'heading', text: 'Head' }, { kind: 'paragraph', text: 'Hello **world**' },
				{ kind: 'quote', text: 'Quote' }, { kind: 'list', ordered: false, items: ['Item'] },
				{ kind: 'list', ordered: true, items: ['First'] }, { kind: 'paragraph', text: '<img>' }
			]);
		expect(parseInline('**world** and *more*').map(({ kind }) => kind)).toEqual(['strong', 'text', 'em']);
	});

	it('preserves copy whitespace, normalizes CRLF and requires a closed exact copy fence', () => {
		expect(parseBlocks('~~~copy Label\r\n leading  \r\n\r\nsecond\r\n~~~'))
			.toEqual([{ kind: 'copy', label: 'Label', text: ' leading  \n\nsecond' }]);
		for (const info of ['copy-x', 'copyright', 'Copy']) {
			expect(parseBlocks('```' + info + '\nvalue\n```')[0].kind).toBe('code');
		}
		expect(parseBlocks('```copy\nvalue')[0].kind).toBe('code');
	});

	it('keeps balanced brackets and excludes punctuation, CJK, inline code and unsafe schemes', () => {
		const tokens = parseInline('https://host/a(b)[c]).，下载 `https://hidden` [X](javascript:bad)');
		expect(tokens.filter(({ kind }) => kind === 'link'))
			.toEqual([{ kind: 'link', text: 'https://host/a(b)[c]', href: 'https://host/a(b)[c]' }]);
		expect(tokens[1]).toMatchObject({ text: ').，下载 ' });
		expect(parseInline('[Mail](mailto:hello@example.com)')[0].kind).toBe('link');
	});

	it('uses rich_content even when empty and enables cards only in rich_content', () => {
		const raw = embed({ title: 'Build' });
		expect(displayContent({ rich_content: '', content: 'Fallback' })).toEqual({ text: '', embeds: true });
		expect(displayContent({ rich_content: raw, content: 'Fallback' })).toEqual({ text: raw, embeds: true });
		expect(displayContent({ rich_content: false, content: raw })).toEqual({ text: raw, embeds: false });
		expect(parseBlocks(raw, true)).toEqual([{ kind: 'embed', card: { title: 'Build' } }]);
		expect(parseBlocks(raw)[0].kind).toBe('code');
	});

	it('treats embed fences inside card text as code and invalid embeds as ordinary code', () => {
		const nested = embed({ title: 'Nested' });
		expect(parseBlocks(embed({ description: nested }), true))
			.toEqual([{ kind: 'embed', card: { description: nested } }]);
		expect(parseBlocks(embed({ text: nested }), true)).toEqual([{ kind: 'embed', card: { text: nested } }]);
		expect(parseBlocks(nested, false)[0].kind).toBe('code');
		expect(parseBlocks('```hiboss-embed\n{} invalid\n```', true)[0].kind).toBe('code');
	});
});
