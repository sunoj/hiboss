<script lang="ts">
	import { t } from '$lib/i18n';
	interface Props {
		bossName: string;
		token: string;
		onDismiss: () => void;
	}

	let { bossName, token, onDismiss }: Props = $props();
	let copied = $state(false);

	async function copy() {
		try {
			await navigator.clipboard.writeText(token);
			copied = true;
			window.setTimeout(() => (copied = false), 2000);
		} catch {
			copied = false;
		}
	}
</script>

<div class="reveal" role="status">
	<div class="head">
		<strong>{t('form.newToken', { name: bossName })}</strong>
		<span class="warn">{t('form.shownOnce')}</span>
	</div>
	<div class="row">
		<input class="token" type="text" readonly value={token} aria-label={t('form.rotatedToken')} />
		<button type="button" class="btn" onclick={copy}>{copied ? t('form.copied') : t('form.copy')}</button>
		<button type="button" class="btn ghost" onclick={onDismiss}>{t('common.dismiss')}</button>
	</div>
</div>

<style>
	.reveal {
		padding: 0.75rem 1rem;
		border: 1px solid color-mix(in srgb, var(--hb-warning) 45%, var(--hb-border));
		background: color-mix(in srgb, var(--hb-warning) 10%, var(--hb-bg-panel));
		border-radius: var(--hb-radius);
		margin-bottom: 0.75rem;
	}
	.head {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
		align-items: baseline;
		margin-bottom: 0.5rem;
	}
	.warn {
		color: var(--hb-warning);
		font-size: 11px;
	}
	.row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.token {
		flex: 1 1 14rem;
		min-width: 0;
		font-family: var(--hb-font-mono);
		font-size: 12px;
		padding: 0.4rem 0.55rem;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-input);
		color: var(--hb-text);
	}
	.btn {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.7rem;
		cursor: pointer;
	}
	.btn:hover {
		background: var(--hb-bg-hover);
	}
	.btn.ghost {
		background: transparent;
		color: var(--hb-text-muted);
	}
</style>
