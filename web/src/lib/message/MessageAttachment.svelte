<!-- Displays one message attachment with image and Markdown preview.
     Reads public attachment bytes only when the viewer opens. -->
<script lang="ts">
	import { t } from '$lib/i18n';
	import { attachmentKind, attachmentName, readMarkdown, type PreviewImage } from './attachment';
	import Markdown from './Markdown.svelte';

	let { href, thumbnail, imageLabel, gallery = [] }: {
		href: string; thumbnail?: string; imageLabel?: string; gallery?: PreviewImage[];
	} = $props();
	let dialog: HTMLDialogElement;
	let type = $state<'image' | 'markdown' | 'file'>('file');
	let loading = $state(false);
	let failed = $state(false);
	let zoom = $state(false);
	const filename = $derived(attachmentName(href));
	let index = $state(-1);
	const current = $derived(gallery[index]);
	const currentHref = $derived(current?.href ?? href);
	const currentLabel = $derived(current?.label || imageLabel || filename);
	let details = $state('');
	let running: AbortController | undefined;
	const guessed = $derived(thumbnail || imageLabel ? 'image' : attachmentKind(filename));

	function step(direction: number) {
		const next = index + direction;
		if (index < 0 || next < 0 || next >= gallery.length) return;
		index = next;
		zoom = false;
		failed = false;
	}

	async function open() {
		running?.abort();
		index = gallery.findIndex((image) => image.href === href);
		loading = false;
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

<button class="file" class:option={!!imageLabel} type="button" onclick={open}>
		{#if thumbnail || imageLabel}<img src={thumbnail || href} alt="" loading="lazy" />{/if}
	{#if imageLabel}
		<span>{t('console.showImage')} · {imageLabel}</span>
	{:else}
		<span><strong>{filename || t('console.attachment')}</strong><br />{t('console.attachment')}</span>
	{/if}
</button>
<dialog bind:this={dialog} onclose={() => running?.abort()} aria-label={currentLabel || t('console.attachment')} onkeydown={(event) => {
		if (type !== 'image' || index < 0 || !['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
		event.preventDefault();
		step(event.key === 'ArrowLeft' ? -1 : 1);
	}}>
	<header>
		<a href={currentHref} target="_blank" rel="noopener noreferrer">{t('console.openOriginal')}</a>
		{#if type === 'image' && index >= 0 && gallery.length > 1}
			<button type="button" disabled={index === 0} onclick={() => step(-1)}>{t('common.previous')}</button>
			<button type="button" disabled={index === gallery.length - 1} onclick={() => step(1)}>{t('common.next')}</button>
		{/if}
		{#if type === 'image'}<button type="button" aria-pressed={zoom} onclick={() => { zoom = !zoom; }}>{t('console.zoom')}</button>{/if}
		<form method="dialog"><button>{t('common.close')}</button></form>
	</header>
	{#if failed}
		<p role="alert">{t('console.attachmentFailed')}</p>
	{:else if loading}
		<p role="status">{t('app.loading')}</p>
	{:else if type === 'image'}
		<img class="large" class:zoom src={currentHref} alt={currentLabel} onerror={() => { failed = true; }} />
	{:else if type === 'markdown'}
		<Markdown text={details} tables />
	{/if}
</dialog>

<style>
	.file, header { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; }
	button { min-height: var(--hit); padding: 8px 12px; border: 1px solid var(--field-border);
		border-radius: var(--r-s); background: var(--surface); text-align: start; }
	.option { width: 100%; }
	.option img { width: auto; max-width: 100%; height: 60px; }
	img { width: 44px; height: 44px; object-fit: contain; }
	dialog { width: min(calc(100% - 24px), 900px); max-height: 90vh; overflow: auto; padding: 16px;
		background: var(--surface); color: var(--ink); border: 1px solid var(--border); border-radius: var(--r-l); }
	dialog::backdrop { background: var(--scrim); }
	header { margin-bottom: 12px; }
	a { color: var(--live); text-decoration: underline; margin-inline-end: auto; }
	.large { width: 100%; height: auto; }
	.zoom { width: 180%; max-width: none; }
</style>
