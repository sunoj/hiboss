<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type {
		AgentResponse,
		CreateRoutingRuleRequest,
		RoutingRuleResponse
	} from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { toasts } from '$lib/stores/toast.svelte';
	import AddRuleForm from './AddRuleForm.svelte';
	import RulesTable from './RulesTable.svelte';
	import {
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
	let creating = $state(false);
	let deletingId = $state<string | null>(null);

	let sortKey = $state<RuleSortKey>('priority');
	let sortDir = $state<SortDir>('desc');

	const agentNames = $derived(buildAgentNameMap(agents));
	const sorted = $derived(sortRules(rules, sortKey, sortDir, agentNames));

	function errMsg(e: unknown): string {
		return e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
	}

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
			error = errMsg(e);
		} finally {
			loading = false;
		}
	}

	function onSort(key: RuleSortKey) {
		const next = nextSortState(sortKey, sortDir, key);
		sortKey = next.key;
		sortDir = next.dir;
	}

	async function onCreate(body: CreateRoutingRuleRequest) {
		const client = auth.client;
		if (!client) {
			toasts.push('Not connected', 'error');
			return;
		}
		creating = true;
		try {
			await client.createRoutingRule(body);
			toasts.push('Routing rule created', 'success');
			await load();
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			creating = false;
		}
	}

	async function onDelete(id: string) {
		const client = auth.client;
		if (!client) {
			toasts.push('Not connected', 'error');
			return;
		}
		if (deletingId) return;
		deletingId = id;
		try {
			await client.deleteRoutingRule(id);
			toasts.push('Routing rule deleted', 'success');
			await load();
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			deletingId = null;
		}
	}

	onMount(() => {
		void load();
	});
</script>

<section class="page">
	<header class="head">
		<div>
			<h1>Routing</h1>
			<p class="sub">路由规则 — priority table and regex matchers</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
			Refresh
		</button>
	</header>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && rules.length === 0}
		<div class="panel"><Skeleton rows={6} height="1.35rem" /></div>
	{:else}
		<AddRuleForm {agents} busy={creating} {onCreate} />

		{#if rules.length === 0}
			<EmptyState
				title="No routing rules"
				detail="Add a regex routing rule, or wait for agents to define them."
			/>
		{:else}
			<RulesTable
				rules={sorted}
				{agentNames}
				{sortKey}
				{sortDir}
				busyId={deletingId}
				{onSort}
				{onDelete}
			/>
		{/if}
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
</style>
