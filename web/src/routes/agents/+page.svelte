<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { AgentConfigResponse, AgentResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { sortAgentsByLastUsed } from './agent-helpers';
	import AgentDrawer from './AgentDrawer.svelte';
	import AgentTable from './AgentTable.svelte';

	let agents = $state<AgentResponse[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let selected = $state<AgentResponse | null>(null);
	let configById = $state<Record<string, AgentConfigResponse>>({});

	const sorted = $derived(sortAgentsByLastUsed(agents));

	function onConfigSaved(agentId: string, config: AgentConfigResponse) {
		configById = { ...configById, [agentId]: config };
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
			const res = await client.agents();
			agents = res.agents ?? [];
			if (selected) {
				selected = agents.find((a) => a.id === selected?.id) ?? null;
			}
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loading = false;
		}
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
			<h1>Agents</h1>
			<p class="sub">智能体 — list, identity, and editable config</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
			Refresh
		</button>
	</header>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && agents.length === 0}
		<div class="panel"><Skeleton rows={8} height="1.4rem" /></div>
	{:else if agents.length === 0}
		<EmptyState
			title="No agents"
			detail="Agents this boss can access will appear here once they are granted."
		/>
	{:else}
		<div class="layout" class:open={selected !== null}>
			<div class="panel table-panel">
				<div class="stream-head">
					<span class="hint">{agents.length} agent{agents.length === 1 ? '' : 's'}</span>
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
	.layout {
		display: flex;
		gap: 0;
		align-items: stretch;
		min-height: calc(100vh - 8rem);
	}
	.panel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
	}
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
