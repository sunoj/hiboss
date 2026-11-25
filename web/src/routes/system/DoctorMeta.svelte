<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import type { ConnectivityResult } from './doctor-helpers';
	import { formatLatency, formatServerTime } from './doctor-helpers';
	import { t } from '$lib/i18n';

	interface Props {
		serverTime: string;
		dbOk: boolean;
		connectivity: ConnectivityResult;
	}

	let { serverTime, connectivity, dbOk }: Props = $props();
</script>

<div class="meta panel">
	<div class="cell">
		<div class="label">{t('form.database')}</div>
		<div class="value" class:fail={!dbOk}>{t(dbOk ? 'status.dbOk' : 'status.dbFail')}</div>
	</div>
	<div class="cell">
		<div class="label">{t('form.apiMe')}</div>
		<div class="value mono" class:fail={!connectivity.ok}>
			{t(connectivity.ok ? 'status.apiOk' : 'status.apiFail')} · {formatLatency(connectivity.latencyMs)}
		</div>
		{#if connectivity.error}
			<div class="err">{connectivity.error}</div>
		{/if}
	</div>
	<div class="cell">
		<div class="label">{t('form.authenticatedBoss')}</div>
		{#if connectivity.ok && connectivity.bossName}
			<div class="boss">
				<AgentIdentity name={connectivity.bossName} size="md" />
				{#if connectivity.bossRole}
					<span class="role">{connectivity.bossRole}</span>
				{/if}
			</div>
		{:else}
			<div class="value muted">{t('form.notVerified')}</div>
		{/if}
	</div>
	{#if serverTime}
		<div class="cell">
			<div class="label">{t('form.serverTime')}</div>
			<div class="value mono">{formatServerTime(serverTime)}</div>
		</div>
	{/if}
</div>

<style>
	@import '../../lib/design/panel.css';
	.meta { padding: 0; border-color: var(--border); box-shadow: none; }
	.cell { display: grid; grid-template-columns: minmax(96px, 28%) minmax(0, 1fr);
		gap: 4px 12px; padding: 12px 16px; align-items: baseline; overflow-wrap: anywhere; }
	.cell + .cell { border-block-start: 1px solid var(--hairline); }
	.label { color: var(--text-2); font: var(--t-footnote); }
	.value {

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
		grid-column: 2;
	}
	.boss {

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
</style>
