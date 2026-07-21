<script lang="ts">
	import type { SessionResponse } from '$lib/api/types';
	import { sessionColor, type SessionStatus } from '$lib/design/semantics';
	import SessionCard from './SessionCard.svelte';

	interface Props {
		status: SessionStatus;
		sessions: SessionResponse[];
		selectedId?: string | null;
		onSelect: (session: SessionResponse) => void;
	}

	let { status, sessions, selectedId = null, onSelect }: Props = $props();

	const color = $derived(sessionColor(status));
</script>

<section class="col" aria-label="{status} sessions">
	<header class="head">
		<span class="dot" style:background={color} aria-hidden="true"></span>
		<h2 style:color={color}>{status}</h2>
		<span class="count" style:color={color}>{sessions.length}</span>
	</header>
	<div class="cards">
		{#if sessions.length === 0}
			<p class="empty-col">No sessions</p>
		{:else}
			{#each sessions as session (session.id)}
				<SessionCard
					{session}
					selected={session.id === selectedId}
					onclick={() => onSelect(session)}
				/>
			{/each}
		{/if}
	</div>
</section>

<style>
	.col {
		display: flex;
		flex-direction: column;
		min-width: 0;
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		overflow: hidden;
		min-height: 12rem;
	}
	.head {
		display: flex;
		align-items: center;
		gap: 0.45rem;
		padding: 0.55rem 0.7rem;
		border-bottom: 1px solid var(--hb-border-subtle);
		background: var(--hb-bg-elevated);
	}
	.dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		flex-shrink: 0;
	}
	h2 {
		margin: 0;
		font-size: 11px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}
	.count {
		margin-left: auto;
		font-variant-numeric: tabular-nums;
		font-weight: 700;
		font-size: 12px;
	}
	.cards {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
		padding: 0.55rem;
		flex: 1;
		overflow-y: auto;
	}
	.empty-col {
		margin: 0.5rem 0;
		text-align: center;
		color: var(--hb-text-dim);
		font-size: 11px;
	}
</style>
