<script lang="ts">
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AgentResponse, GroupResponse } from '$lib/api/types';
	import { displayDescription, hasDescription, memberCountLabel } from './groupHelpers';
	import MemberEditor from './MemberEditor.svelte';

	interface Props {
		group: GroupResponse;
		agents: AgentResponse[];
		busy?: boolean;
		onDelete: (groupId: string) => void;
		onAddMember: (groupId: string, agentId: string) => void;
		onRemoveMember: (groupId: string, agentId: string) => void;
	}

	let { group, agents, busy = false, onDelete, onAddMember, onRemoveMember }: Props =
		$props();

	let editing = $state(false);

	const desc = $derived(displayDescription(group.description));
	const descPresent = $derived(hasDescription(group.description));
	const members = $derived(memberCountLabel(group.member_count));
	const when = $derived(formatRelativeTime(group.created_at));

	function confirmDelete() {
		if (busy) return;
		const ok = confirm(`Delete group “${group.name}”? This cannot be undone.`);
		if (ok) onDelete(group.id);
	}
</script>

<article class="card" aria-label={group.name}>
	<div class="top">
		<h2 class="name" title={group.name}>{group.name}</h2>
		<span class="members" title={members}>{members}</span>
	</div>
	<p class="desc" class:muted={!descPresent}>{desc}</p>
	<div class="meta">
		<span class="when">Created {when}</span>
		<span class="id" title={group.id}>{group.id.slice(0, 8)}</span>
	</div>
	<div class="actions">
		<button
			type="button"
			class="btn"
			disabled={busy}
			onclick={() => (editing = !editing)}
		>
			{editing ? 'Hide members' : 'Edit members'}
		</button>
		<button type="button" class="btn danger" disabled={busy} onclick={confirmDelete}>
			Delete
		</button>
	</div>
	{#if editing}
		<MemberEditor
			{agents}
			{busy}
			onAdd={(agentId) => onAddMember(group.id, agentId)}
			onRemove={(agentId) => onRemoveMember(group.id, agentId)}
			onClose={() => (editing = false)}
		/>
	{/if}
</article>

<style>
	.card {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
		padding: 0.85rem 1rem;
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		box-shadow: var(--hb-shadow);
		min-width: 0;
	}
	.top {
		display: flex;
		align-items: baseline;
		gap: 0.5rem;
		min-width: 0;
	}
	.name {
		margin: 0;
		font-size: 14px;
		font-weight: 700;
		letter-spacing: -0.01em;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		min-width: 0;
	}
	.members {
		margin-left: auto;
		flex-shrink: 0;
		font-size: 11px;
		font-weight: 650;
		color: var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 14%, transparent);
		border: 1px solid color-mix(in srgb, var(--hb-accent) 30%, var(--hb-border));
		border-radius: var(--hb-radius-sm);
		padding: 0.12rem 0.4rem;
	}
	.desc {
		margin: 0;
		font-size: 12px;
		color: var(--hb-text-muted);
		line-height: 1.4;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}
	.desc.muted {
		color: var(--hb-text-dim);
		font-style: italic;
	}
	.meta {
		display: flex;
		justify-content: space-between;
		gap: 0.5rem;
		font-size: 10px;
		color: var(--hb-text-dim);
	}
	.id {
		font-family: var(--hb-font-mono);
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		margin-top: 0.15rem;
	}
	.btn {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.28rem 0.55rem;
		font: inherit;
		font-size: 11px;
		color: var(--hb-text);
		cursor: pointer;
	}
	.btn:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.btn.danger {
		border-color: color-mix(in srgb, var(--hb-danger) 40%, var(--hb-border));
		color: var(--hb-danger);
	}
	.btn:disabled {
		opacity: 0.55;
		cursor: wait;
	}
</style>
