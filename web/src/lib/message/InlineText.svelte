<!-- Renders typed inline tokens as Svelte elements.
     User text is escaped by Svelte. -->
<script lang="ts">
	import { parseInline } from './inline';
	let { text, markdown = true }: { text: string; markdown?: boolean } = $props();
</script>

{#each parseInline(text, markdown) as token}
	{#if token.kind === 'link'}
		<a href={token.href} target="_blank" rel="noopener noreferrer">{token.text}</a>
	{:else if token.kind === 'code'}
		<code>{token.text}</code>
	{:else if token.kind === 'strong'}
		<strong>{token.text}</strong>
	{:else if token.kind === 'em'}
		<em>{token.text}</em>
	{:else}
		{token.text}
	{/if}
{/each}

<style>
	a { color: var(--live); text-decoration: underline; overflow-wrap: anywhere; }
	code { background: var(--surface-2); font: var(--t-mono); border-radius: 4px; padding-inline: 4px; }
	:global(:is(:lang(zh), :lang(ja), :lang(ko))) em { font-style: normal; font-weight: 600; }
</style>
