<script lang="ts">
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { AgentConfigResponse, AgentResponse } from '$lib/api/types';
	import { t } from '$lib/i18n';
	import { sortAgentsByLastUsed } from './agent-helpers';
	import AgentDrawer from './AgentDrawer.svelte';
	import AgentTable from './AgentTable.svelte';

	let agents = $state<AgentResponse[]>([]);
	const loadState = new LoadState();
	let selected = $state<AgentResponse | null>(null);
	let configById = $state<Record<string, AgentConfigResponse>>({});

	const sorted = $derived(sortAgentsByLastUsed(agents));

	function onConfigSaved(agentId: string, config: AgentConfigResponse) {
		configById = { ...configById, [agentId]: config };
	}

	async function load() {
		await loadState.run(async (client) => {
			const res = await client.agents();
			agents = res.agents ?? [];
			if (selected) {
				selected = agents.find((a) => a.id === selected?.id) ?? null;
			}
		});
	}

	function selectAgent(agent: AgentResponse) {
		selected = selected?.id === agent.id ? null : agent;
	}

	onMount(() => {
		void load();
	});
</script>

<section class="page">
	<header class="head">
		<div>
			<h1>{t('page.agents')}</h1>
			<p class="sub">{t('page.agentsSub')}</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loadState.loading}>
			{t('common.refresh')}
		</button>
	</header>

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
		<div class="layout" class:open={selected !== null}>
			<div class="panel table-panel">
				<div class="stream-head">
					<span class="hint">{t('common.agents', { count: agents.length })}</span>
				</div>
				<AgentTable
					agents={sorted}
					selectedId={selected?.id ?? null}
					onSelect={selectAgent}
				/>
			</div>
			{#if selected}
				<AgentDrawer
					agent={selected}
					config={configById[selected.id] ?? null}
					onClose={() => (selected = null)}
					onConfigSaved={onConfigSaved}
				/>
			{/if}
		</div>
	{/if}
</section>

<style>
	@import '../../lib/design/page-header.css';
	@import '../../lib/design/panel.css';
	@import '../../lib/design/shared/split-view.css';
	.table-panel {
		flex: 1;
		min-width: 0;
		padding: 0;
		overflow: hidden;
	}
	.layout.open .table-panel {
		border-top-right-radius: 0;
		border-bottom-right-radius: 0;
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
		.layout.open .table-panel {
			border-radius: var(--hb-radius);
		}
	}
</style>
