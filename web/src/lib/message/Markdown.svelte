<!-- Renders the console Markdown subset and server-owned embed cards.
     Embed text enters this renderer with card support disabled. -->
<script lang="ts">
	import Markdown from './Markdown.svelte';
	import CopyBlock from './CopyBlock.svelte';
	import EmbedCard from './EmbedCard.svelte';
	import InlineText from './InlineText.svelte';
	import { parseBlocks } from './blocks';

	let { text, embeds = false }: { text: string; embeds?: boolean } = $props();
	const blocks = $derived(parseBlocks(text, embeds));
</script>

<div class="markdown">
	{#each blocks as block}
		{#if block.kind === 'paragraph'}
			<p><InlineText text={block.text} /></p>
		{:else if block.kind === 'heading'}
			<h3><InlineText text={block.text} /></h3>
		{:else if block.kind === 'quote'}
			<blockquote><InlineText text={block.text} /></blockquote>
		{:else if block.kind === 'code'}
			<!-- svelte-ignore a11y_no_noninteractive_tabindex -->
			<pre tabindex="0"><code>{block.text}</code></pre>
		{:else if block.kind === 'copy'}
			<CopyBlock text={block.text} label={block.label} />
		{:else if block.kind === 'embed'}
			{#if block.card.text !== undefined}
				<Markdown text={block.card.text} />
			{:else}
				<EmbedCard card={block.card} />
			{/if}
		{:else if block.kind === 'list'}
			<svelte:element this={block.ordered ? 'ol' : 'ul'}>
				{#each block.items as item}<li><InlineText text={item} /></li>{/each}
			</svelte:element>
		{/if}
	{/each}
</div>

<style>
	.markdown { display: grid; gap: 12px; overflow-wrap: anywhere; min-width: 0; font: var(--t-body); }
	p, blockquote { white-space: pre-wrap; margin: 0; }
	h3 { font: var(--t-headline); margin: 0; }
	ul, ol { margin: 0; padding-inline-start: 24px; }
	blockquote { border-inline-start: 3px solid var(--hairline); padding-inline-start: 12px; color: var(--text-2); }
	pre { background: var(--surface-2); border-radius: var(--r-m); overflow: auto; padding: 12px; margin: 0; }
	code { font: var(--t-mono); }
</style>
