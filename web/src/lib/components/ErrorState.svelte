<script lang="ts">
	import { t } from '$lib/i18n';
	interface Props {
		title?: string;
		message: string;
		onRetry?: () => void;
	}

	let { title = t('common.requestFailed'), message, onRetry }: Props = $props();
</script>

<div class="err" role="alert">
	<div class="title">{title}</div>
	<p>{message}</p>
	{#if onRetry}
		<button type="button" onclick={onRetry}>{t('common.retry')}</button>
	{/if}
</div>

<style>
	.err {
		padding: 1rem;
		border: 1px solid color-mix(in srgb, var(--hb-danger) 40%, var(--hb-border));
		background: color-mix(in srgb, var(--hb-danger) 10%, var(--hb-bg-panel));
		border-radius: var(--hb-radius);
		color: var(--hb-text);
	}
	.title {
		font-weight: 650;
		color: var(--hb-danger);
		margin-bottom: 0.25rem;
	}
	p {
		margin: 0 0 0.65rem;
		color: var(--hb-text-muted);
		word-break: break-word;
	}
	button {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.3rem 0.7rem;
		cursor: pointer;
	}
	button:hover {
		background: var(--hb-bg-hover);
	}
</style>
