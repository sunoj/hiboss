<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { BossChannelConfig } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import AgentChannelGroup from './AgentChannelGroup.svelte';
	import { CLI_NOTE, groupChannelsByAgent } from './groupChannels';

	let channels = $state<BossChannelConfig[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);

	const groups = $derived(groupChannelsByAgent(channels));

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
			channels = await client.channels();
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
			<h1>Channels</h1>
			<p class="sub">渠道 — connectivity board by agent</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
			Refresh
		</button>
	</header>

	<p class="cli-note" role="note">{CLI_NOTE}</p>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && channels.length === 0}
		<div class="board">
			{#each Array(3) as _, i (i)}
				<div class="skel"><Skeleton rows={4} height="1.2rem" /></div>
			{/each}
		</div>
	{:else if channels.length === 0}
		<EmptyState
			title="No channels configured"
			detail="Configure Discord, Telegram, email, or API delivery via the hiboss CLI. Secrets never appear here."
		/>
	{:else}
		<div class="board" role="list">
			{#each groups as group (group.agent_id)}
				<div role="listitem">
					<AgentChannelGroup {group} />
				</div>
			{/each}
		</div>
	{/if}
</section>

<style>
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 1rem;
		margin-bottom: 0.65rem;
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
	.cli-note {
		margin: 0 0 1rem;
		padding: 0.45rem 0.65rem;
		font-size: 12px;
		color: var(--hb-text-muted);
		background: var(--hb-bg-input);
		border: 1px solid var(--hb-border-subtle);
		border-radius: var(--hb-radius-sm);
	}
	.board {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
		gap: 0.75rem;
	}
	.skel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
	}
</style>
