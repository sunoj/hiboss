<script lang="ts">
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { BossChannelConfig } from '$lib/api/types';
	import { configuredLabel, publicFields } from './groupChannels';

	interface Props {
		channel: BossChannelConfig;
	}

	let { channel }: Props = $props();

	const fields = $derived(publicFields(channel));
	const on = $derived(Boolean(channel.configured));
</script>

<li class="row" class:ok={on} class:off={!on}>
	<span class="light" aria-hidden="true"></span>
	<div class="main">
		<div class="top">
			<span class="name">{channel.channel}</span>
			<span class="state">{configuredLabel(on)}</span>
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
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--hb-text-dim);
	}
	.ok .state {
		color: var(--hb-success);
	}
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
