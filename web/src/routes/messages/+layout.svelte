<script lang="ts">
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import MessageRow from '$lib/components/MessageRow.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { MessageResponse } from '$lib/api/types';
	import { apiErrorMessage } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import { inputs } from '$lib/decisions/inputs.svelte';
	import { displayContent } from '$lib/message/blocks';
	import { page } from '$app/state';
	import '$lib/design/console-split.css';
	import MessageFilters from './MessageFilters.svelte';
	import MessageSessionGroup from './MessageSessionGroup.svelte';
	import {
		DEFAULT_FILTERS,
		PAGE_SIZE,
		applyLocalFilters,
		buildMessagesQuery,
		groupBySession,
		hasMorePages,
		type MessageFilterState,
		type ViewMode
	} from './message-helpers';

	let filters = $state<MessageFilterState>({ ...DEFAULT_FILTERS });
	let viewMode = $state<ViewMode>('flat');
	let messages = $state<MessageResponse[]>([]);
	let total = $state(0);
	const loadState = new LoadState();
	let loadingMore = $state(false);
	let { children } = $props();

	const chipLabels = {
		all: 'console.all', needs: 'console.needs', fromAgents: 'console.fromAgents',
		fromMe: 'console.fromMe', integrations: 'console.integrations'
	} as const;
	const chips = Object.keys(chipLabels) as (keyof typeof chipLabels)[];
	let chip = $state<(typeof chips)[number]>('all');
	const visible = $derived(applyLocalFilters(chip === 'needs' ? inputs.messages : messages, filters)
		.filter((message) => {
			if (chip === 'needs' && inputs.settled.has(message.id)) return false;
			if (chip === 'fromAgents' && message.direction !== 'agent_to_boss') return false;
			if (chip === 'fromMe' && message.direction !== 'boss_to_agent') return false;
			if (chip === 'integrations' && !message.metadata?.integration && message.metadata?.source !== 'webhook') {
				return false;
			}
			const search = filters.search.trim().toLocaleLowerCase();
			return !search || [message.body, displayContent(message.metadata).text]
				.some((text) => text.toLocaleLowerCase().includes(search));
		}));
	const groups = $derived(groupBySession(visible));
	const canLoadMore = $derived(chip !== 'needs' && hasMorePages(messages.length, total));

	async function load() {
		await loadState.run(async (client) => {
			const query = buildMessagesQuery({ ...filters, search: '' }, { limit: PAGE_SIZE, offset: 0 });
			const msg = await client.messages(query);
			messages = msg.messages;
			total = msg.total;
		});
	}

	async function loadMore() {
		const client = auth.client;
		if (!client || loadingMore || !canLoadMore) return;
		loadingMore = true;
		loadState.error = null;
		try {
			const query = buildMessagesQuery({ ...filters, search: '' }, {
				limit: PAGE_SIZE,
				offset: messages.length
			});
			const msg = await client.messages(query);
			const seen = new Set(messages.map((m) => m.id));
			messages = [...messages, ...msg.messages.filter((m) => !seen.has(m.id))];
			total = msg.total;
		} catch (e) {
			loadState.error = apiErrorMessage(e);
		} finally {
			loadingMore = false;
		}
	}

	function messageHref(message: MessageResponse) {
		return '/messages/' + encodeURIComponent(message.id) + (filters.search.trim() ? '?search=1' : '');
	}

	function clearFilters() {
		filters = { ...DEFAULT_FILTERS };
		chip = 'all';
		void load();
	}

	onMount(() => {
		void load();
	});
</script>

<div class="console-split" data-detail={page.params.id && page.url.searchParams.get('from') !== 'today'
	&& page.url.searchParams.get('from') !== 'session' ? '' : undefined}>
<section class="messages console-list" hidden={page.params.id &&
	['today', 'session'].includes(page.url.searchParams.get('from') ?? '')}>
	<header class="head">
		<div>
			<h1>{t('page.messages')}</h1>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loadState.loading}>
			{t('common.refresh')}
		</button>
	</header>

	<div class="quick" role="group" aria-label={t('page.messages')}>
		{#each chips as value}
			<button type="button" aria-pressed={chip === value} onclick={() => { chip = value; }}>
				{t(chipLabels[value])}
			</button>
		{/each}
	</div>
	<MessageFilters
		{filters}
		{viewMode}
		onChange={(next) => (filters = next)}
		onViewMode={(mode) => (viewMode = mode)}
		onSubmit={load}
	/>

	{#if loadState.error}
		<ErrorState message={loadState.error} onRetry={load} />
	{:else if loadState.loading && messages.length === 0}
		<div class="panel"><Skeleton rows={8} /></div>
	{:else if chip === 'needs' && !inputs.loaded}
		<p role="status">{t('console.checking')}</p>
	{:else if visible.length === 0}
		<EmptyState
			title={t('page.noMessageMatch')}
			detail={t('page.noMessageMatchDetail')}
		/>
		<button type="button" onclick={clearFilters}>{t('console.clearFilters')}</button>
	{:else}
		<div class="panel stream">
			<div class="stream-head">
				<span class="hint">
					{t('common.messageSummary', { loaded: messages.length, total, filtered: visible.length, mode: viewMode === 'grouped' ? t('page.bySession') : t('page.flat') })}
				</span>
			</div>

			{#if viewMode === 'flat'}
				<div class="feed">
					{#each visible as message (message.id)}
						<a class="row-btn" href={messageHref(message)}
							aria-current={page.params.id === message.id ? 'page' : undefined}>
							<MessageRow {message} />
						</a>
					{/each}
				</div>
			{:else}
				{#each groups as group (group.key)}
					<MessageSessionGroup {group} hrefFor={messageHref} />
				{/each}
			{/if}

		</div>
	{/if}
			{#if canLoadMore}
				<div class="more">
					<button type="button" class="load-more" disabled={loadingMore} onclick={loadMore}>
						{loadingMore ? t('app.loading') : t('page.loadMore', { count: PAGE_SIZE })}
					</button>
				</div>
			{/if}
</section>

{#if children}{@render children()}{/if}
</div>

<style>
	@import '../../lib/design/panel.css';
	@import '../../lib/design/shared/stream-panel.css';
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
	.feed {
		display: flex;
		flex-direction: column;
	}
	.row-btn {
		display: block;
		width: 100%;
		padding: 0;
		margin: 0;
		border: none;
		background: transparent;
		text-align: left;
		cursor: pointer;
		color: inherit;
		font: inherit;
	}
	.row-btn:focus-visible {
		outline: 2px solid var(--hb-accent);
		outline-offset: -2px;
	}
	.more {
		padding: 0.75rem 1rem;
		border-top: 1px solid var(--hb-border-subtle);
		display: flex;
		justify-content: center;
	}
	.load-more {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.4rem 0.9rem;
		cursor: pointer;
		font-weight: 600;
		color: var(--hb-text);
	}
	.load-more:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.load-more:disabled {
		opacity: 0.6;
		cursor: wait;
	}
	.quick { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 12px; }
	.quick button { min-height: var(--hit); padding-inline: 10px; background: var(--surface);
		border: 1px solid var(--border); border-radius: var(--r-pill); }
	.quick button[aria-pressed="true"] { background: var(--live-soft); color: var(--live); }
</style>
