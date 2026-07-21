<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import MessageRow from '$lib/components/MessageRow.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { MessageResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import MessageDrawer from './MessageDrawer.svelte';
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
	let loading = $state(true);
	let loadingMore = $state(false);
	let error = $state<string | null>(null);
	let selected = $state<MessageResponse | null>(null);

	const visible = $derived(applyLocalFilters(messages, filters));
	const groups = $derived(groupBySession(visible));
	const canLoadMore = $derived(hasMorePages(messages.length, total));

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
			const query = buildMessagesQuery(filters, { limit: PAGE_SIZE, offset: 0 });
			const msg = await client.messages(query);
			messages = msg.messages;
			total = msg.total;
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loading = false;
		}
	}

	async function loadMore() {
		const client = auth.client;
		if (!client || loadingMore || !canLoadMore) return;
		loadingMore = true;
		error = null;
		try {
			const query = buildMessagesQuery(filters, {
				limit: PAGE_SIZE,
				offset: messages.length
			});
			const msg = await client.messages(query);
			const seen = new Set(messages.map((m) => m.id));
			messages = [...messages, ...msg.messages.filter((m) => !seen.has(m.id))];
			total = msg.total;
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loadingMore = false;
		}
	}

	function openMessage(message: MessageResponse) {
		selected = message;
	}

	function onMessageUpdated(updated: MessageResponse) {
		const parentId = updated.reply_to;
		if (parentId) {
			messages = messages.map((m) =>
				m.id === parentId ? { ...m, status: 'replied' } : m
			);
			if (selected?.id === parentId) selected = { ...selected, status: 'replied' };
			return;
		}
		messages = messages.map((m) => (m.id === updated.id ? { ...m, ...updated } : m));
		if (selected?.id === updated.id) selected = { ...selected, ...updated };
	}

	onMount(() => {
		void load();
	});
</script>

<section class="messages">
	<header class="head">
		<div>
			<h1>Messages</h1>
			<p class="sub">消息中心 — full stream, filters, session grouping, detail drawer</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>Refresh</button>
	</header>

	<MessageFilters
		{filters}
		{viewMode}
		onChange={(next) => (filters = next)}
		onViewMode={(mode) => (viewMode = mode)}
		onSubmit={load}
	/>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && messages.length === 0}
		<div class="panel"><Skeleton rows={8} /></div>
	{:else if visible.length === 0}
		<EmptyState
			title="No messages match"
			detail="Try widening direction, clearing priority chips, or searching a different term."
		/>
	{:else}
		<div class="panel stream">
			<div class="stream-head">
				<span class="hint">
					Loaded {messages.length} of {total} · filtered {visible.length} · {viewMode ===
					'grouped'
						? 'by session'
						: 'flat'}
				</span>
			</div>

			{#if viewMode === 'flat'}
				<div class="feed">
					{#each visible as message (message.id)}
						<button type="button" class="row-btn" onclick={() => openMessage(message)}>
							<MessageRow {message} />
						</button>
					{/each}
				</div>
			{:else}
				{#each groups as group (group.key)}
					<MessageSessionGroup {group} onSelect={openMessage} />
				{/each}
			{/if}

			{#if canLoadMore}
				<div class="more">
					<button type="button" class="load-more" disabled={loadingMore} onclick={loadMore}>
						{loadingMore ? 'Loading…' : `Load more (${PAGE_SIZE})`}
					</button>
				</div>
			{/if}
		</div>
	{/if}
</section>

{#if selected}
	<MessageDrawer
		message={selected}
		onClose={() => (selected = null)}
		onUpdated={onMessageUpdated}
	/>
{/if}

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
</style>
