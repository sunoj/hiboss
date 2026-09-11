<!-- Channel row with enabled switch and inline request feedback.
     Depends on channel helpers, API types, and i18n. -->
<script lang="ts">
	import { t } from '$lib/i18n';
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { BossChannelConfig } from '$lib/api/types';
	import { configuredLabel, publicFields } from './groupChannels';

	interface Props {
		channel: BossChannelConfig;
		disabled: boolean;
		error?: string;
		warning?: boolean;
		onToggle: (channel: BossChannelConfig) => Promise<void>;
	}

	let { channel, disabled, error, warning, onToggle }: Props = $props();

	const fields = $derived(publicFields(channel));
	const on = $derived(channel.enabled === 1);
</script>

<li class="row" class:ok={on} class:off={!on}>
	<span class="light" aria-hidden="true"></span>
	<div class="main">
		<div class="top">
			<span class="name">{channel.channel}</span>
			<button type="button" class="state" role="switch" aria-checked={on}
				aria-label={t('channel.toggle', { channel: channel.channel, agent: channel.agent_name })}
				{disabled} onclick={() => onToggle(channel)}>{configuredLabel(on)}</button>
			<span class="when" title={channel.created_at}>{formatRelativeTime(channel.created_at)}</span>
		</div>
		{#if fields.length > 0}
			<dl class="meta">
				{#each fields as field (field.key)}
					<div class="pair">
						<dt>{field.key}</dt>
						<dd title={field.value}>{field.value}</dd>
					</div>
				{/each}
			</dl>
		{/if}
		{#if error}<p class="feedback error" role="alert">{error}</p>{/if}
		{#if warning}<p class="feedback warning" role="status">{t('channel.noEnabledWarning')}</p>{/if}
	</div>
</li>

<style>
	.row {
		display: grid;
		grid-template-columns: 12px 1fr;
		gap: 0.65rem;
		align-items: start;
		padding: 0.55rem 0.65rem;
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-input);
		border: 1px solid var(--hb-border-subtle);
	}
	.light {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		margin-top: 0.35rem;
	}
	.ok .light {
		background: var(--hb-success);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--hb-success) 25%, transparent);
	}
	.off .light {
		background: var(--hb-text-dim);
	}
	.main {
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	.top {
		display: flex;
		align-items: baseline;
		gap: 0.55rem;
		flex-wrap: wrap;
	}
	.name {
		text-transform: lowercase;
		font-family: var(--hb-font-mono);
		font-size: 12px;
		font-weight: 600;
	}
	.state {
		border: 1px solid currentColor;
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-panel);
		padding: 0.25rem 0.55rem;
		cursor: pointer;
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--hb-text-dim);
	}
	.ok .state {
		color: var(--hb-success);
	}
	.state:disabled { opacity: 0.6; cursor: default; }
	.state:focus-visible { outline: 2px solid var(--hb-success); outline-offset: 2px; }
	.feedback { margin: 0; font-size: 12px; overflow-wrap: anywhere; }
	.error { color: var(--hb-danger); }
	.warning { color: var(--hb-warning); }
	.when {
		margin-left: auto;
		font-size: 11px;
		color: var(--hb-text-dim);
	}
	.meta {
		margin: 0;
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem 0.75rem;
	}
	.pair {
		display: inline-flex;
		gap: 0.3rem;
		align-items: baseline;
		min-width: 0;
		font-size: 11px;
	}
	dt {
		margin: 0;
		color: var(--hb-text-muted);
		font-family: var(--hb-font-mono);
	}
	dd {
		margin: 0;
		color: var(--hb-text);
		font-family: var(--hb-font-mono);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		max-width: 14rem;
	}
</style>
