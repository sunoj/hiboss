<script lang="ts">
	import { toasts } from '$lib/stores/toast.svelte';
	import { t } from '$lib/i18n';
</script>

{#if toasts.items.length > 0}
	<div class="stack" aria-live="polite">
		{#each toasts.items as toast (toast.id)}
			<div class="toast" class:success={toast.tone === 'success'} class:error={toast.tone === 'error'} class:warning={toast.tone === 'warning'}>
				<span>{toast.message}</span>
				<button type="button" aria-label={t('common.dismiss')} onclick={() => toasts.dismiss(toast.id)}>×</button>
			</div>
		{/each}
	</div>
{/if}

<style>
	.stack {
		position: fixed;
		right: 1rem;
		bottom: 1rem;
		z-index: 1000;
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
		max-width: min(360px, calc(100vw - 2rem));
	}
	.toast {
		display: flex;
		align-items: flex-start;
		gap: 0.6rem;
		padding: 0.65rem 0.75rem;
		background: var(--hb-bg-elevated);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		box-shadow: var(--hb-shadow);
	}
	.success {
		border-color: color-mix(in srgb, var(--hb-success) 50%, var(--hb-border));
	}
	.error {
		border-color: color-mix(in srgb, var(--hb-danger) 50%, var(--hb-border));
	}
	.warning {
		border-color: color-mix(in srgb, var(--hb-warning) 50%, var(--hb-border));
	}
	button {
		margin-left: auto;
		border: none;
		background: transparent;
		cursor: pointer;
		color: var(--hb-text-muted);
		font-size: 1rem;
		line-height: 1;
		padding: 0;
	}
</style>
