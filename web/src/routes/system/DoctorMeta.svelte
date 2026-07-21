<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import type { ConnectivityResult } from './doctor-helpers';
	import { formatLatency, formatServerTime } from './doctor-helpers';

	interface Props {
		serverTime: string;
		connectivity: ConnectivityResult;
	}

	let { serverTime, connectivity }: Props = $props();
</script>

<div class="meta panel">
	<div class="cell">
		<div class="label">Server time</div>
		<div class="value mono">{formatServerTime(serverTime)}</div>
	</div>
	<div class="cell">
		<div class="label">API latency</div>
		<div class="value mono" class:fail={!connectivity.ok}>
			{formatLatency(connectivity.latencyMs)}
		</div>
		{#if connectivity.error}
			<div class="err">{connectivity.error}</div>
		{/if}
	</div>
	<div class="cell">
		<div class="label">Authenticated boss</div>
		{#if connectivity.ok && connectivity.bossName}
			<div class="boss">
				<AgentIdentity name={connectivity.bossName} size="md" />
				{#if connectivity.bossRole}
					<span class="role">{connectivity.bossRole}</span>
				{/if}
			</div>
		{:else}
			<div class="value muted">Not verified</div>
		{/if}
	</div>
</div>

<style>
	.panel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
	}
	.meta {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 0.85rem;
	}
	.cell {
		min-width: 0;
	}
	.label {
		color: var(--hb-text-muted);
		font-size: 11px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.value {
		margin-top: 0.35rem;
		font-size: 0.95rem;
		font-weight: 600;
	}
	.mono {
		font-family: var(--hb-font-mono);
		font-variant-numeric: tabular-nums;
	}
	.muted {
		color: var(--hb-text-dim);
		font-weight: 500;
	}
	.fail {
		color: var(--hb-danger);
	}
	.err {
		margin-top: 0.25rem;
		color: var(--hb-danger);
		font-size: 11px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.boss {
		margin-top: 0.35rem;
		display: flex;
		align-items: center;
		gap: 0.5rem;
		min-width: 0;
	}
	.role {
		flex-shrink: 0;
		padding: 0.1rem 0.4rem;
		border-radius: var(--hb-radius-sm);
		font-size: 10px;
		font-weight: 650;
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 14%, transparent);
		border: 1px solid transparent;
	}
	@media (max-width: 720px) {
		.meta {
			grid-template-columns: 1fr;
		}
	}
</style>
