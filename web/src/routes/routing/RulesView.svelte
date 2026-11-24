<script lang="ts">
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type {
		AgentResponse,
		CreateRoutingRuleRequest,
		RoutingRuleResponse
	} from '$lib/api/types';
	import { apiErrorMessage } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
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
	const loadState = new LoadState();
	let creating = $state(false);
	let deletingId = $state<string | null>(null);

	let sortKey = $state<RuleSortKey>('priority');
	let sortDir = $state<SortDir>('desc');

	const agentNames = $derived(buildAgentNameMap(agents));
	const sorted = $derived(sortRules(rules, sortKey, sortDir, agentNames));

	async function load() {
		await loadState.run(async (client) => {
			const [rulesRes, agentsRes] = await Promise.all([
				client.routingRules(),
				client.agents()
			]);
			rules = rulesRes.rules ?? [];
			agents = agentsRes.agents ?? [];
		});
	}

	function onSort(key: RuleSortKey) {
		const next = nextSortState(sortKey, sortDir, key);
		sortKey = next.key;
		sortDir = next.dir;
	}

	async function onCreate(body: CreateRoutingRuleRequest) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		creating = true;
		try {
			await client.createRoutingRule(body);
			toasts.push(t('form.routingCreated'), 'success');
			await load();
		} catch (e) {
			toasts.push(apiErrorMessage(e), 'error');
		} finally {
			creating = false;
		}
	}

	async function onDelete(id: string) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		if (deletingId) return;
		deletingId = id;
		try {
			await client.deleteRoutingRule(id);
			toasts.push(t('form.routingDeleted'), 'success');
			await load();
		} catch (e) {
			toasts.push(apiErrorMessage(e), 'error');
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
			<h1>{t('page.routing')}</h1>
			<p class="sub">{t('page.routingSub')}</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loadState.loading}>
			{t('common.refresh')}
		</button>
	</header>

	{#if loadState.error}
		<ErrorState message={loadState.error} onRetry={load} />
	{:else if loadState.loading && rules.length === 0}
		<div class="panel"><Skeleton rows={6} height="1.35rem" /></div>
	{:else}
		<AddRuleForm {agents} busy={creating} {onCreate} />

		{#if rules.length === 0}
			<EmptyState
				title={t('page.noRouting')}
				detail={t('page.noRoutingDetail')}
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
	@import '../../lib/design/page-header.css';
	@import '../../lib/design/panel.css'
</style>
