<!-- Displays a validated integration card and its field rows.
     Markdown children cannot render additional cards. -->
<script lang="ts">
	import { formatDateTime, t } from '$lib/i18n';
	import { fieldRows, type Embed } from './embed';
	import { safeLink } from './inline';
	import InlineText from './InlineText.svelte';
	import Markdown from './Markdown.svelte';

	let { card }: { card: Embed } = $props();
	const color = $derived(card.color == null ? 'var(--border)' : '#' + card.color.toString(16).padStart(6, '0'));
	const image = $derived(safeLink(card.image));
	const thumbnail = $derived(safeLink(card.thumbnail));
	const href = $derived(safeLink(card.url));
</script>

<article aria-label={t('console.embedCard', { title: card.title ?? '' })} style:border-inline-start-color={color}>
	{#if thumbnail}<img class="thumbnail" src={thumbnail} alt="" loading="lazy" />{/if}
	{#if card.author}<Markdown text={card.author} />{/if}
	{#if card.title}
		<h3>
			{#if href}<a {href} target="_blank" rel="noopener noreferrer">{card.title}</a>
			{:else}<InlineText text={card.title} />{/if}
		</h3>
	{/if}
	{#if card.description}<Markdown text={card.description} />{/if}
	{#if card.fields?.length}
		<dl>
			{#each fieldRows(card.fields) as row}
				{#each row as field}
					<div class:inline={field.inline}>
						<dt><Markdown text={field.name} /></dt>
						<dd><Markdown text={field.value} /></dd>
					</div>
				{/each}
				{#if row[0].inline && row.length < 3}<div class="filler" aria-hidden="true"></div>{/if}
			{/each}
		</dl>
	{/if}
	{#if image}<img class="image" src={image} alt="" loading="lazy" />{/if}
	{#if card.footer || (card.timestamp && Number.isFinite(Date.parse(card.timestamp)))}
		<footer>
			{#if card.footer}<Markdown text={card.footer} />{/if}
			{#if card.timestamp && Number.isFinite(Date.parse(card.timestamp))}
				<time datetime={card.timestamp} title={formatDateTime(card.timestamp)}>
					{formatDateTime(card.timestamp)}
				</time>
			{/if}
		</footer>
	{/if}
</article>

<style>
	article {
		display: flow-root;
		max-width: 560px;
		padding: 12px 16px;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-inline-start-width: 4px;
		border-radius: var(--r-m);
	}
	article > :global(* + *) { margin-block-start: 8px; }
	h3 { font: var(--t-headline); margin-block-end: 0; }
	a { color: var(--live); text-decoration: underline; }
	dl { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px; margin-block-end: 0; }
	dl > div { grid-column: 1 / -1; }
	dl > .inline, dl > .filler { grid-column: auto; }
	dl > .filler { grid-column-end: -1; }
	dt :global(p) { font-weight: 600; }
	dd { margin: 0; color: var(--text-2); }
	.thumbnail { float: inline-end; width: 64px; height: 64px; object-fit: contain; margin-inline-start: 8px; }
	.image { max-width: 100%; }
	footer, footer :global(p) { font: var(--t-caption); color: var(--text-3); }
</style>
