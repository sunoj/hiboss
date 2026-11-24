<!-- Wraps selectable, exact copy values with clipboard feedback.
     Uses a selection fallback when clipboard access fails. -->
<script lang="ts">
	import { onDestroy } from 'svelte';
	import { t } from '$lib/i18n';

	let { text, label = '' }: { text: string; label?: string } = $props();
	let code: HTMLElement;
	let feedback = $state<'copied' | 'select' | null>(null);
	let reset: ReturnType<typeof setTimeout>;
	onDestroy(() => clearTimeout(reset));

	async function copy(): Promise<void> {
		clearTimeout(reset);
		try {
			await navigator.clipboard.writeText(text);
			feedback = 'copied';
			reset = setTimeout(() => { feedback = null; }, 2000);
		} catch {
			const range = document.createRange();
			range.selectNodeContents(code);
			const selection = window.getSelection();
			selection?.removeAllRanges();
			selection?.addRange(range);
			feedback = 'select';
		}
	}
</script>

<div class="copy">
	<div class="bar">
		<span>{label}</span>
		<button type="button" onclick={copy}>{feedback === 'copied' ? t('form.copied') : t('form.copy')}</button>
	</div>
	<pre bind:this={code}>{text}</pre>
	<span aria-live="polite">{feedback === 'select' ? t('console.copySelect') : feedback === 'copied'
		? t('form.copied') : ''}</span>
</div>

<style>
	.copy { background: var(--surface-2); border: 1px solid var(--border); border-radius: var(--r-m); padding: 12px; }
	.bar { display: flex; align-items: center; justify-content: space-between; gap: 8px; font: var(--t-caption); }
	button { min-height: var(--hit); background: var(--surface); border: 1px solid var(--border); border-radius: 8px; }
	pre { font: var(--t-mono); white-space: pre-wrap; overflow-wrap: anywhere; margin: 4px 0 0; }
</style>
