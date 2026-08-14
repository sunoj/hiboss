<script lang="ts">
	import { onMount } from 'svelte';
	import ChannelLights from '$lib/components/ChannelLights.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import KpiCard from '$lib/components/KpiCard.svelte';
	import MessageRow from '$lib/components/MessageRow.svelte';
	import PriorityBars from '$lib/components/PriorityBars.svelte';
	import SessionStatusList from '$lib/components/SessionStatusList.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { BossOverview, MessageResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';

	let overview = $state<BossOverview | null>(null);
	let messages = $state<MessageResponse[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	async function load() {
		const client = auth.client;
		if (!client) {
			error = 'Not connected';
			loading = false;
			return;
		}
		loading = true;
		error = null;
		try {
			const [ov, msg] = await Promise.all([
				client.overview(),
				client.messages({ direction: 'all', limit: 10 })
			]);
			overview = ov;
			messages = msg.messages;
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		void load();
	});
</script>

<section class="dash">
	<header class="head">
		<div>
			<h1>{t('page.dashboard')}</h1>
			<p class="sub">{t('page.dashboardSub')}</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>{t('common.refresh')}</button>
	</header>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && !overview}
		<div class="grid kpis">
			{#each Array(4) as _, i (i)}
				<div class="panel"><Skeleton rows={2} height="1.6rem" /></div>
			{/each}
		</div>
		<div class="grid mid">
			<div class="panel"><Skeleton rows={5} /></div>
			<div class="panel"><Skeleton rows={5} /></div>
			<div class="panel"><Skeleton rows={4} /></div>
		</div>
	{:else if overview}
		<div class="grid kpis">
			<KpiCard
				label={t('page.activeSessions')}
				value={overview.kpis.activeSessions}
				hint={t('page.working', { count: overview.kpis.workingSessions })}
				tone="accent"
			/>
			<KpiCard
				label={t('page.pendingDecisions')}
				value={overview.kpis.pendingDecisions}
				hint={t('page.pendingDecisionsHint')}
				tone={overview.kpis.pendingDecisions > 0 ? 'warn' : 'default'}
			/>
			<KpiCard
				label={t('page.blockingPending')}
				value={overview.kpis.blockingPending}
				hint={t('page.blockingPendingHint')}
				tone={overview.kpis.blockingPending > 0 ? 'danger' : 'default'}
			/>
			<KpiCard
				label={t('page.unread1h')}
				value={overview.kpis.unread1h}
				hint={t('page.unread1hHint')}
			/>
		</div>

		<div class="grid mid">
			<div class="panel">
				<h2>{t('page.priorityDistribution')}</h2>
				<p class="hint">{t('page.last24h')}</p>
				<PriorityBars distribution={overview.priorityDistribution} />
			</div>
			<div class="panel">
				<h2>{t('page.sessionStatus')}</h2>
				<p class="hint">{t('page.seenLast24h')}</p>
				<SessionStatusList counts={overview.sessionStatus} />
			</div>
			<div class="panel">
				<h2>{t('page.channelHealth')}</h2>
				<p class="hint">{t('page.configuredPaths')}</p>
				<ChannelLights channels={overview.channels} />
			</div>
		</div>

		<div class="panel stream">
			<div class="stream-head">
				<h2>{t('page.recentMessages')}</h2>
				<span class="hint">{t('common.latestDirections')}</span>
			</div>
			{#if messages.length === 0}
				<EmptyState title={t('page.noRecentMessages')} detail={t('page.noRecentMessagesDetail')} />
			{:else}
				<div class="feed">
					{#each messages as message (message.id)}
						<MessageRow {message} />
					{/each}
				</div>
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
	.kpis {
		grid-template-columns: repeat(4, minmax(0, 1fr));
	}
	.mid {
		grid-template-columns: 1.2fr 1fr 1fr;
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
	.stream {
		padding: 0;
		overflow: hidden;
	}
	.stream-head {
		display: flex;
		justify-content: space-between;
		align-items: baseline;
		padding: 0.85rem 1rem 0.5rem;
	}
	.stream-head .hint {
		margin: 0;
	}
	.feed {
		border-top: 1px solid var(--hb-border-subtle);
	}
	@media (max-width: 1100px) {
		.kpis,
		.mid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}
	@media (max-width: 720px) {
		.kpis,
		.mid {
			grid-template-columns: 1fr;
		}
	}
</style>
