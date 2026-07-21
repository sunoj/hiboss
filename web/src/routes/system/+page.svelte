<script lang="ts">
	import { onMount } from 'svelte';
	import ChannelLights from '$lib/components/ChannelLights.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import KpiCard from '$lib/components/KpiCard.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { BossSystemResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { toasts } from '$lib/stores/toast.svelte';
	import DoctorMeta from './DoctorMeta.svelte';
	import StatusBeacon from './StatusBeacon.svelte';
	import {
		channelHealthHint,
		emptyConnectivity,
		healthLabel,
		overallHealth,
		type ConnectivityResult
	} from './doctor-helpers';

	let system = $state<BossSystemResponse | null>(null);
	let connectivity = $state<ConnectivityResult>(emptyConnectivity());
	let loading = $state(true);
	let error = $state<string | null>(null);

	function errMsg(e: unknown): string {
		return e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
	}

	async function probeMe(
		client: NonNullable<typeof auth.client>
	): Promise<ConnectivityResult> {
		const started = performance.now();
		try {
			const me = await client.me();
			return {
				ok: true,
				latencyMs: Math.round(performance.now() - started),
				bossName: me.name,
				bossRole: me.role,
				error: null
			};
		} catch (e) {
			return {
				ok: false,
				latencyMs: Math.round(performance.now() - started),
				bossName: null,
				bossRole: null,
				error: errMsg(e)
			};
		}
	}

	async function runChecks(notify = false) {
		const client = auth.client;
		if (!client) {
			error = 'Not connected';
			loading = false;
			if (notify) toasts.push('Not connected', 'error');
			return;
		}
		loading = true;
		error = null;
		try {
			const [sys, meResult] = await Promise.all([client.system(), probeMe(client)]);
			system = sys;
			connectivity = meResult;
			if (notify) {
				const tone = overallHealth(sys.db_ok, meResult.ok);
				const label = healthLabel(tone);
				toasts.push(
					`Doctor: ${label}`,
					tone === 'ok' ? 'success' : tone === 'degraded' ? 'warning' : 'error'
				);
			}
		} catch (e) {
			error = errMsg(e);
			connectivity = emptyConnectivity();
			if (notify) toasts.push(error, 'error');
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		void runChecks(false);
	});
</script>

<section class="doctor">
	<header class="head">
		<div>
			<h1>System / Doctor</h1>
			<p class="sub">系统 — connectivity self-check, channel health, live stats</p>
		</div>
		<button
			type="button"
			class="refresh"
			onclick={() => runChecks(true)}
			disabled={loading}
		>
			{loading ? 'Checking…' : 'Re-run checks'}
		</button>
	</header>

	{#if error}
		<ErrorState message={error} onRetry={() => runChecks(true)} />
	{:else if loading && !system}
		<div class="grid hero">
			<div class="panel"><Skeleton rows={4} height="1.4rem" /></div>
			<div class="panel"><Skeleton rows={3} height="1.2rem" /></div>
		</div>
		<div class="grid kpis">
			{#each Array(3) as _, i (i)}
				<div class="panel"><Skeleton rows={2} height="1.6rem" /></div>
			{/each}
		</div>
		<div class="panel"><Skeleton rows={5} /></div>
	{:else if system}
		<div class="grid hero">
			<StatusBeacon dbOk={system.db_ok} meOk={connectivity.ok} />
			<DoctorMeta serverTime={system.server_time} {connectivity} />
		</div>

		<div class="grid kpis">
			<KpiCard
				label="Active sessions"
				value={system.active_sessions}
				hint="seen recently"
				tone="accent"
			/>
			<KpiCard
				label="Pending decisions"
				value={system.pending_decisions}
				hint="option messages awaiting pick"
				tone={system.pending_decisions > 0 ? 'warn' : 'default'}
			/>
			<KpiCard
				label="Channels"
				value={`${system.channels.filter((c) => c.configured).length}/${system.channels.length}`}
				hint={channelHealthHint(system.channels)}
				tone={system.channels.some((c) => c.configured) ? 'default' : 'warn'}
			/>
		</div>

		<div class="panel">
			<h2>Channel health</h2>
			<p class="hint">Configured delivery paths from server doctor snapshot</p>
			{#if system.channels.length === 0}
				<p class="empty">No channel rows returned.</p>
			{:else}
				<ChannelLights channels={system.channels} />
			{/if}
		</div>
	{/if}
</section>

<style>
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 1rem;
		margin-bottom: 1rem;
	}
	h1 {
		margin: 0;
		font-size: 1.25rem;
		font-weight: 700;
		letter-spacing: -0.02em;
	}
	.sub {
		margin: 0.15rem 0 0;
		color: var(--hb-text-muted);
	}
	.refresh {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-panel);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.7rem;
		cursor: pointer;
	}
	.refresh:disabled {
		opacity: 0.6;
		cursor: wait;
	}
	.grid {
		display: grid;
		gap: 0.75rem;
		margin-bottom: 0.75rem;
	}
	.hero {
		grid-template-columns: 1.1fr 1.4fr;
		align-items: stretch;
	}
	.kpis {
		grid-template-columns: repeat(3, minmax(0, 1fr));
	}
	.panel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
	}
	h2 {
		margin: 0;
		font-size: 12px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.hint {
		margin: 0.15rem 0 0.7rem;
		color: var(--hb-text-dim);
		font-size: 11px;
	}
	.empty {
		margin: 0;
		color: var(--hb-text-dim);
		font-size: 12px;
	}
	@media (max-width: 1100px) {
		.hero,
		.kpis {
			grid-template-columns: 1fr;
		}
	}
</style>
