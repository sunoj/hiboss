<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { GroupResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import BroadcastComposer from './BroadcastComposer.svelte';
	import GroupCard from './GroupCard.svelte';
	import { WRITE_DISABLED_NOTE, sortGroupsByName } from './groupHelpers';

	let groups = $state<GroupResponse[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	const sorted = $derived(sortGroupsByName(groups));

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
			const res = await client.groups();
			groups = res.groups ?? [];
		} catch (e) {
			error = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
		} finally {
			loading = false;
		}
	}

	onMount(() => {
		void load();
	});
</script>

<section class="page">
	<header class="head">
		<div>
			<h1>Groups</h1>
			<p class="sub">智能体分组 — group list and whole-group broadcast</p>
		</div>
		<div class="head-actions">
			<button type="button" class="create" disabled title={WRITE_DISABLED_NOTE}>
				Create group
			</button>
			<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
				Refresh
			</button>
		</div>
	</header>

	<p class="write-note" role="note">
		Create / members / broadcast: <em>{WRITE_DISABLED_NOTE}</em>
	</p>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && groups.length === 0}
		<div class="layout">
			<div class="grid">
				{#each Array(4) as _, i (i)}
					<div class="skel"><Skeleton rows={4} height="1.2rem" /></div>
				{/each}
			</div>
			<div class="skel composer-skel"><Skeleton rows={6} /></div>
		</div>
	{:else}
		<div class="layout">
			<div class="main">
				{#if sorted.length === 0}
					<EmptyState
						title="No groups yet"
						detail="Agent groups owned by accessible agents will appear here."
					/>
				{:else}
					<div class="grid" role="list">
						{#each sorted as group (group.id)}
							<div role="listitem">
								<GroupCard {group} />
							</div>
						{/each}
					</div>
				{/if}
			</div>
			<aside class="side">
				<BroadcastComposer groups={sorted} />
			</aside>
		</div>
	{/if}
</section>

<style>
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 1rem;
		margin-bottom: 0.55rem;
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
	.head-actions {
		display: flex;
		gap: 0.45rem;
		flex-shrink: 0;
	}
	.refresh,
	.create {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-panel);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.7rem;
		font: inherit;
		font-size: 12px;
		color: var(--hb-text);
		cursor: pointer;
	}
	.refresh:disabled {
		opacity: 0.6;
		cursor: wait;
	}
	.create:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}
	.write-note {
		margin: 0 0 0.85rem;
		font-size: 11px;
		color: var(--hb-warning);
	}
	.write-note em {
		font-style: normal;
		font-weight: 650;
	}
	.layout {
		display: grid;
		grid-template-columns: minmax(0, 1.6fr) minmax(240px, 0.9fr);
		gap: 0.75rem;
		align-items: start;
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
		gap: 0.75rem;
	}
	.skel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
	}
	.composer-skel {
		min-height: 12rem;
	}
	@media (max-width: 900px) {
		.layout {
			grid-template-columns: 1fr;
		}
	}
</style>
