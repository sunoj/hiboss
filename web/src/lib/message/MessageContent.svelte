<!-- Renders preferred message details with a grapheme-safe text preview.
     Copy blocks and integration cards stay intact. -->
<script lang="ts">
	import { t, getLocale } from '$lib/i18n';
	import type { MessageMetadata } from '$lib/api/types';
	import { displayContent } from './blocks';
	import { safeLink } from './inline';
	import MessageAttachment from './MessageAttachment.svelte';
	import Markdown from './Markdown.svelte';

	let { metadata, expanded = false }: { metadata: MessageMetadata | null; expanded?: boolean } = $props();
	let open = $state(false);
	const content = $derived(displayContent(metadata));
	const href = $derived(safeLink(metadata?.file_url));
	const thumbnail = $derived(safeLink(metadata?.file_thumbnail_url));
	const lines = $derived(content.text.split('\n'));
	const characters = $derived(Array.from(new Intl.Segmenter(getLocale()).segment(content.text)));
	const long = $derived(!content.embeds && !/^s*(?:`{3,}|~{3,})/m.test(content.text)
		&& (characters.length > 1200 || lines.length > 14));
	const preview = $derived(characters.slice(0, 600).map(({ segment }) => segment).join('').split('\n')
		.slice(0, 8).join('\n') + '…');
</script>

{#if content.text}
	<Markdown text={long && !open && !expanded ? preview : content.text} embeds={content.embeds} />
	{#if long && !expanded}
		<button type="button" aria-expanded={open} onclick={() => open = !open}>
			{t(open ? 'console.collapse' : 'console.showFull')}
		</button>
	{/if}
{/if}

{#if href}<MessageAttachment {href} {thumbnail} />{/if}

<style>
	button { min-height: var(--hit); color: var(--live); border: 0; background: transparent; }
</style>
