<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { AuditEntry } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import AuditFilters from './AuditFilters.svelte';
	import AuditPager from './AuditPager.svelte';
	import AuditTable from './AuditTable.svelte';
	import {
		DEFAULT_FILTERS,
		applyLocalSearch,
		buildAuditQuery,
		type AuditFilterState
	} from './audit-helpers';

	let filters = $state<AuditFilterState>({ ...DEFAULT_FILTERS });
	let entries = $state<AuditEntry[]>([]);
	let total = $state(0);
	let loading = $state(true);
	let error = $state<string | null>(null);

	const visible = $derived(applyLocalSearch(entries, filters.search));

	async function load(nextFilters: AuditFilterState = filters) {
		const client = auth.client;
		if (!client) {
			error = 'Not connected';
			loading = false;
			return;
		}
		loading = true;
		error = null;
		try {
			const res = await client.audit(buildAuditQuery(nextFilters));
			entries = res.entries ?? [];
			total = res.total ?? 0;
			filters = nextFilters;
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loading = false;
		}
	}

	function onFiltersChange(next: AuditFilterState) {
		filters = next;
	}

	function onApply() {
		void load({ ...filters, offset: 0 });
	}

	function onPage(offset: number) {
		void load({ ...filters, offset });
	}

	onMount(() => {
		void load();
	});
</script>

<section class="audit">
	<header class="head">
		<div>
			<h1>Audit</h1>
			<p class="sub">审计 — searchable operation and delivery log</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
			Refresh
		</button>
	</header>

	<AuditFilters {filters} onChange={onFiltersChange} onSubmit={onApply} />

	{#if error}
		<ErrorState message={error} onRetry={() => load()} />
	{:else if loading && entries.length === 0}
		<div class="panel"><Skeleton rows={8} /></div>
	{:else if entries.length === 0}
		<EmptyState
			title="No audit entries"
			detail="Operations will appear here as agents and bosses act on the system."
		/>
	{:else if visible.length === 0}
		<EmptyState
			title="No rows match search"
			detail="Clear the page search or widen actor/action filters, then Apply."
		/>
	{:else}
		<div class="panel stream">
			<div class="stream-head">
				<span class="hint">
					Server page {Math.floor(filters.offset / filters.limit) + 1} · limit
					{filters.limit} · total {total}
					{#if filters.search.trim()}
						· showing {visible.length} after search
					{/if}
				</span>
			</div>
			<AuditTable entries={visible} />
			<AuditPager
				offset={filters.offset}
				limit={filters.limit}
				{total}
				visibleCount={entries.length}
				disabled={loading}
				{onPage}
			/>
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
	.panel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
	}
	.stream {
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
</style>
