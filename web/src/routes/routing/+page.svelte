<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { AgentResponse, RoutingRuleResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import RulesTable from './RulesTable.svelte';
	import {
		WRITE_NOTE,
		buildAgentNameMap,
		nextSortState,
		sortRules,
		type RuleSortKey,
		type SortDir
	} from './sortRules';

	let rules = $state<RoutingRuleResponse[]>([]);
	let agents = $state<AgentResponse[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	let sortKey = $state<RuleSortKey>('priority');
	let sortDir = $state<SortDir>('desc');

	const agentNames = $derived(buildAgentNameMap(agents));
	const sorted = $derived(sortRules(rules, sortKey, sortDir, agentNames));

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
			const [rulesRes, agentsRes] = await Promise.all([
				client.routingRules(),
				client.agents()
			]);
			rules = rulesRes.rules ?? [];
			agents = agentsRes.agents ?? [];
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loading = false;
		}
	}

	function onSort(key: RuleSortKey) {
		const next = nextSortState(sortKey, sortDir, key);
		sortKey = next.key;
		sortDir = next.dir;
	}

	onMount(() => {
		void load();
	});
</script>

<section class="page">
	<header class="head">
		<div>
			<h1>Routing</h1>
			<p class="sub">路由规则 — priority table and regex matchers (read-only writes)</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
			Refresh
		</button>
	</header>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && rules.length === 0}
		<div class="panel"><Skeleton rows={6} height="1.35rem" /></div>
	{:else if rules.length === 0}
		<div class="empty-wrap">
			<div class="toolbar">
				<button type="button" class="add" disabled title={WRITE_NOTE}>Add rule</button>
				<p class="note" role="note">{WRITE_NOTE}</p>
			</div>
			<EmptyState
				title="No routing rules"
				detail="Regex routing rules will appear here once agents define them."
			/>
		</div>
	{:else}
		<RulesTable rules={sorted} {agentNames} {sortKey} {sortDir} {onSort} />
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
	.panel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
	}
	.empty-wrap {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		box-shadow: var(--hb-shadow);
		overflow: hidden;
	}
	.toolbar {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.65rem 1rem;
		padding: 0.75rem 1rem;
		border-bottom: 1px solid var(--hb-border-subtle);
	}
	.note {
		margin: 0;
		font-size: 11px;
		color: var(--hb-warning);
	}
	.add {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.3rem 0.65rem;
		color: var(--hb-text);
		opacity: 0.45;
		cursor: not-allowed;
	}
	.empty-wrap :global(.empty) {
		margin: 0.75rem 1rem 1rem;
	}
</style>
