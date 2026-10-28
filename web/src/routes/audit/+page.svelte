<script lang="ts">
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { AuditEntry } from '$lib/api/types';
	import { t } from '$lib/i18n';
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
	const loadState = new LoadState();

	const visible = $derived(applyLocalSearch(entries, filters.search));

	async function load(nextFilters: AuditFilterState = filters) {
		await loadState.run(async (client) => {
			const res = await client.audit(buildAuditQuery(nextFilters));
			entries = res.entries ?? [];
			total = res.total ?? 0;
			filters = nextFilters;
		});
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
			<h1>{t('page.audit')}</h1>
			<p class="sub">{t('page.auditSub')}</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loadState.loading}>
			{t('common.refresh')}
		</button>
	</header>

	<AuditFilters {filters} onChange={onFiltersChange} onSubmit={onApply} />

	{#if loadState.error}
		<ErrorState message={loadState.error} onRetry={() => load()} />
	{:else if loadState.loading && entries.length === 0}
		<div class="panel"><Skeleton rows={8} /></div>
	{:else if entries.length === 0}
		<EmptyState
			title={t('page.noAudit')}
			detail={t('page.noAuditDetail')}
		/>
	{:else if visible.length === 0}
		<EmptyState
			title={t('page.noAuditSearch')}
			detail={t('page.noAuditSearchDetail')}
		/>
	{:else}
		<div class="panel stream">
			<div class="stream-head">
				<span class="hint">
					{t('pager.summary', { page: Math.floor(filters.offset / filters.limit) + 1, limit: filters.limit, total, ...(filters.search.trim() ? { showing: visible.length } : {}) })}
				</span>
			</div>
			<AuditTable entries={visible} />
			<AuditPager
				offset={filters.offset}
				limit={filters.limit}
				{total}
				visibleCount={entries.length}
				disabled={loadState.loading}
				{onPage}
			/>
		</div>
	{/if}
</section>

<style>
	@import '../../lib/design/page-header.css';
	@import '../../lib/design/panel.css';
	@import '../../lib/design/shared/stream-panel.css'
</style>
