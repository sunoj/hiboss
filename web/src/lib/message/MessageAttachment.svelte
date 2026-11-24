<!-- Displays one message attachment with image and Markdown preview.
     Reads public attachment bytes only when the viewer opens. -->
<script lang="ts">
	import { t } from '$lib/i18n';
	import { attachmentKind, attachmentName, readMarkdown } from './attachment';
	import Markdown from './Markdown.svelte';

	let { href, thumbnail }: { href: string; thumbnail?: string } = $props();
	let dialog: HTMLDialogElement;
	let type = $state<'image' | 'markdown' | 'file'>('file');
	let loading = $state(false);
	let failed = $state(false);
	let zoom = $state(false);
	let details = $state('');
	let running: AbortController | undefined;
	const filename = $derived(attachmentName(href));
	const guessed = $derived(thumbnail ? 'image' : attachmentKind(filename));

	async function open() {
		type = guessed;
		failed = false;
		zoom = false;
		details = '';
		dialog.showModal();
		if (type === 'image') return;
		loading = true;
		const controller = new AbortController();
		running = controller;
		try {
			const response = await fetch(href, { signal: controller.signal });
			const mime = response.headers.get('content-type') ?? '';
			const disposition = response.headers.get('content-disposition') ?? '';
			const suggested = disposition.match(/filename="?([^";]+)"?/i)?.[1] ?? '';
			if (mime.startsWith('image/') && response.ok) type = 'image';
			if (type === 'markdown' || /^(?:text|application)\/markdown\b/i.test(mime)
				|| attachmentKind(suggested) === 'markdown') {
				type = 'markdown';
				details = await readMarkdown(response);
			} else {
				await response.body?.cancel();
			}
		} catch {
			if (!controller.signal.aborted) failed = true;
		} finally {
			if (running === controller) loading = false;
		}
	}
</script>

<button class="file" type="button" onclick={open}>
	{#if thumbnail}<img src={thumbnail} alt="" loading="lazy" />{/if}
	<span><strong>{filename || t('console.attachment')}</strong><br />{t('console.attachment')}</span>
</button>
<dialog bind:this={dialog} onclose={() => running?.abort()} aria-label={filename || t('console.attachment')}>
	<header>
		<a {href} target="_blank" rel="noopener noreferrer">{t('console.openOriginal')}</a>
		{#if type === 'image'}<button type="button" aria-pressed={zoom} onclick={() => { zoom = !zoom; }}>{t('console.zoom')}</button>{/if}
		<form method="dialog"><button>{t('common.close')}</button></form>
	</header>
	{#if failed}
		<p role="alert">{t('console.attachmentFailed')}</p>
	{:else if loading}
		<p role="status">{t('app.loading')}</p>
	{:else if type === 'image'}
		<img class="large" class:zoom src={href} alt={filename} />
	{:else if type === 'markdown'}
		<Markdown text={details} tables />
	{/if}
</dialog>

<style>
	.file, header { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
	button { min-height: var(--hit); padding: 8px 12px; border: 1px solid var(--field-border);
		border-radius: var(--r-s); background: var(--surface); text-align: start; }
	img { width: 44px; height: 44px; object-fit: contain; }
	dialog { width: min(calc(100% - 24px), 900px); max-height: 90vh; overflow: auto; padding: 16px;
		background: var(--surface); color: var(--ink); border: 1px solid var(--border); border-radius: var(--r-l); }
	dialog::backdrop { background: var(--scrim); }
	header { margin-bottom: 12px; }
	a { color: var(--live); text-decoration: underline; margin-inline-end: auto; }
	.large { width: 100%; height: auto; }
	.zoom { width: 180%; max-width: none; }
</style>
