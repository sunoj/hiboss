<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { MessageResponse, SessionResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import { groupSessionsByStatus } from './groupSessions';
	import SessionColumn from './SessionColumn.svelte';
	import SessionDrawer from './SessionDrawer.svelte';

	let sessions = $state<SessionResponse[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	let selected = $state<SessionResponse | null>(null);
	let messages = $state<MessageResponse[]>([]);
	let msgLoading = $state(false);
	let msgError = $state<string | null>(null);

	const columns = $derived(groupSessionsByStatus(sessions));

	async function load() {
		const client = auth.client;
		if (!client) {
			error = t('top.offline');
			loading = false;
			return;
		}
		loading = true;
		error = null;
		try {
			const res = await client.sessions();
			sessions = res.sessions ?? [];
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loading = false;
		}
	}

	async function loadMessages(sessionId: string) {
		const client = auth.client;
		if (!client) {
			msgError = t('top.offline');
			msgLoading = false;
			return;
		}
		msgLoading = true;
		msgError = null;
		try {
			const res = await client.messages({ session: sessionId, limit: 20 });
			messages = res.messages ?? [];
		} catch (e) {
			msgError = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
			messages = [];
		} finally {
			msgLoading = false;
		}
	}

	function selectSession(session: SessionResponse) {
		selected = session;
		messages = [];
		void loadMessages(session.id);
	}

	function closeDrawer() {
		selected = null;
		messages = [];
		msgError = null;
	}

	function retryMessages() {
		if (selected) void loadMessages(selected.id);
	}

	onMount(() => {
		void load();
	});
</script>

<section class="page">
	<header class="head">
		<div>
			<h1>{t('page.sessions')}</h1>
			<p class="sub">{t('page.sessionsSub')}</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
			{t('common.refresh')}
		</button>
	</header>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && sessions.length === 0}
		<div class="board skeleton-board">
			{#each Array(5) as _, i (i)}
				<div class="skel-col"><Skeleton rows={5} height="1.4rem" /></div>
			{/each}
		</div>
	{:else if sessions.length === 0}
		<EmptyState
			title={t('page.noSessions')}
			detail={t('page.noSessionsDetail')}
		/>
	{:else}
		<div class="layout" class:open={selected !== null}>
			<div class="board" role="list">
				{#each columns as column (column.status)}
					<SessionColumn
						status={column.status}
						sessions={column.sessions}
						selectedId={selected?.id ?? null}
						onSelect={selectSession}
					/>
				{/each}
			</div>
			{#if selected}
				<SessionDrawer
					session={selected}
					{messages}
					loading={msgLoading}
					error={msgError}
					onClose={closeDrawer}
					onRetry={retryMessages}
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
	.board {
		display: grid;
		grid-template-columns: repeat(5, minmax(160px, 1fr));
		gap: 0.65rem;
		flex: 1;
		min-width: 0;
		overflow-x: auto;
		align-content: start;
	}
	.layout.open .board {
		padding-right: 0.5rem;
	}
	.skeleton-board .skel-col {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.75rem;
	}
	@media (max-width: 1100px) {
		.board {
			grid-template-columns: repeat(3, minmax(180px, 1fr));
		}
	}
	@media (max-width: 720px) {
		.layout {
			flex-direction: column;
		}
		.board {
			grid-template-columns: 1fr;
		}
	}
</style>
