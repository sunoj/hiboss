<script lang="ts">
	import { agentDirectory } from '$lib/stores/agents.svelte';
	import { page } from '$app/state';
	import { auth } from '$lib/stores/auth.svelte';
	import type { JoinRequest } from '$lib/api/client';
	import GroupsView from '../groups/GroupsView.svelte';
	import ChannelsView from '../channels/ChannelsView.svelte';
	import JoinRequests from './JoinRequests.svelte';
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { BossChannelConfig } from '$lib/api/types';
	import { t } from '$lib/i18n';
	import { sortAgentsByLastUsed } from './agent-helpers';
	import '$lib/design/console-split.css';
	import AgentTable from './AgentTable.svelte';

	const agents = $derived(agentDirectory.rows);
	const loadState = new LoadState();
	let { children } = $props();
	let joins = $state<JoinRequest[] | null>(null);
	let search = $state('');
	let channels = $state<BossChannelConfig[] | null>(null);
	const withoutChannels = $derived(channels && agents.filter((agent) =>
		!channels?.some((channel) => channel.agent_id === agent.id && channel.configured && channel.enabled === 1)));
	const tab = $derived(page.url.searchParams.get('tab'));
	const sorted = $derived(sortAgentsByLastUsed(agents.filter((agent) => [agent.name, agent.role,
		...agent.project_slugs ?? []].some((value) => value?.toLowerCase().includes(search.trim().toLowerCase())))));

	async function load(force = false) {
		await loadState.run(async (client) => {
			await agentDirectory.load(client, force);
		});
	}

	async function loadJoins() {
		if (auth.connection?.boss?.role !== 'admin' || !auth.client) return;
		try { joins = (await auth.client.pendingJoins()).requests; }
		catch { joins = null; }
	}

	onMount(() => {
		void load();
		void loadJoins();
		void auth.client?.channels().then((rows) => { channels = Array.isArray(rows) ? rows : null; })
			.catch(() => undefined);
	});
</script>

<h1>{t('page.agents')}</h1>
<nav class="section-tabs" aria-label={t('nav.agents')}>
	<a href="/agents" aria-current={!tab ? 'page' : undefined}>{t('nav.agents')}</a>
	<a href="/agents?tab=groups" aria-current={tab === 'groups' ? 'page' : undefined}>{t('nav.groups')}</a>
	{#if joins}
		<a href="/agents?tab=join" aria-current={tab === 'join' ? 'page' : undefined}>
			{t('console.joinRequests')} · {joins.length}
		</a>
	{/if}
</nav>
{#if tab === 'groups'}
	<GroupsView />
{:else if tab === 'channels'}
	<ChannelsView />
{:else if tab === 'join' && joins}
	<JoinRequests requests={joins} onResolved={(id) => { joins = joins?.filter((row) => row.id !== id) ?? null; }} />
{:else}
<div class="console-split" data-detail={page.params.id ? '' : undefined}>
<section class="page console-list">
	<header class="head">
		<button type="button" class="refresh" onclick={() => load(true)} disabled={loadState.loading}>
			{t('common.refresh')}
		</button>
	</header>

	<label>{t('console.agentSearch')} <input type="search" bind:value={search} /></label>
	{#if loadState.error}
		<ErrorState message={loadState.error} onRetry={load} />
	{:else if loadState.loading && agents.length === 0}
		<div class="panel"><Skeleton rows={8} height="1.4rem" /></div>
	{:else if agents.length === 0}
		<EmptyState
			title={t('page.noAgents')}
			detail={t('page.noAgentsDetail')}
		/>
	{:else if sorted.length === 0}
		<EmptyState title={t('page.noAgents')} />
	{:else}
		<div class="layout">
			<div class="panel table-panel">
				<div class="stream-head">
					<span class="hint">{t('common.agents', { count: agents.length })}</span>
				</div>
				<AgentTable
					agents={sorted}
					selectedId={page.params.id ?? null}
				/>
			</div>
		</div>
	{/if}
	{#if withoutChannels?.length}
		<p class="channel-warning">
			{t('console.noEnabledChannels', { agents: withoutChannels.map(({ name }) => name).join(', ') })}
		</p>
	{/if}
</section>
{@render children()}
</div>
{/if}

<style>
	@import '../../lib/design/panel.css';
	@import '../../lib/design/section-tabs.css';
	.layout { min-width: 0; }
	/* Page headings and refresh controls shared by the console routes.
 * Inlined by vitePreprocess so each consuming component retains scoped selectors. */
.head {
	display: flex;
	justify-content: space-between;
	align-items: flex-start;
	gap: 1rem;
	margin-bottom: 1rem;
}
h1 {
	margin: 0;
	font: var(--t-large);
	letter-spacing: -0.02em;
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
	.table-panel {
		flex: 1;
		min-width: 0;
		padding: 0;
		overflow: hidden;
	}
	.stream-head {
		padding: 0.65rem 1rem;
		border-bottom: 1px solid var(--hb-border-subtle);
	}
	.hint {
		color: var(--hb-text-dim);
		font-size: 11px;
	}
	@media (max-width: 720px) {
		.layout {
			flex-direction: column;
		}
	}
	.channel-warning { background: var(--signal-soft); color: var(--signal);
		border-radius: var(--r-m); padding: 12px 16px; }

	input { min-height: var(--hit); margin-bottom: 12px; }
</style>
