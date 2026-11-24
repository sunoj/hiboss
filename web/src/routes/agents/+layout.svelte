<script lang="ts">
	import { page } from '$app/state';
	import { goto } from '$app/navigation';
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
	import type { AgentResponse } from '$lib/api/types';
	import { t } from '$lib/i18n';
	import { sortAgentsByLastUsed } from './agent-helpers';
	import '$lib/design/console-split.css';
	import AgentTable from './AgentTable.svelte';

	let agents = $state<AgentResponse[]>([]);
	const loadState = new LoadState();
	let { children } = $props();
	let joins = $state<JoinRequest[] | null>(null);
	let search = $state('');
	const tab = $derived(page.url.searchParams.get('tab'));
	const sorted = $derived(sortAgentsByLastUsed(agents.filter((agent) => [agent.name, agent.role,
		...agent.project_slugs ?? []].some((value) => value?.toLowerCase().includes(search.trim().toLowerCase())))));

	async function load() {
		await loadState.run(async (client) => {
			agents = (await client.agents()).agents ?? [];
		});
	}

	async function loadJoins() {
		if (auth.connection?.boss?.role !== 'admin' || !auth.client) return;
		try { joins = (await auth.client.pendingJoins()).requests; }
		catch { joins = null; }
	}

	function selectAgent(agent: AgentResponse) {
		void goto('/agents/' + encodeURIComponent(agent.id));
	}

	onMount(() => {
		void load();
		void loadJoins();
	});
</script>

<nav class="tabs" aria-label={t('nav.agents')}>
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
		<div>
			<h1>{t('page.agents')}</h1>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loadState.loading}>
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
	{:else}
		<div class="layout">
			<div class="panel table-panel">
				<div class="stream-head">
					<span class="hint">{t('common.agents', { count: agents.length })}</span>
				</div>
				<AgentTable
					agents={sorted}
					selectedId={page.params.id ?? null}
					onSelect={selectAgent}
				/>
			</div>
		</div>
	{/if}
</section>
{@render children()}
</div>
{/if}

<style>
	@import '../../lib/design/panel.css';
	@import '../../lib/design/shared/split-view.css';
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
	font-size: 1.25rem;
	font-weight: 700;
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
	.tabs { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
	.tabs a { display: flex; align-items: center; min-height: var(--hit); padding-inline: 12px; border-radius: 8px; }
	.tabs a[aria-current="page"] { background: var(--live-soft); color: var(--live); }
	input { min-height: var(--hit); margin-bottom: 12px; }
</style>
