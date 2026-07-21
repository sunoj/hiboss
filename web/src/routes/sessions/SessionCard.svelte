<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { SessionResponse } from '$lib/api/types';
	import { coerceSessionStatus, sessionColor } from '$lib/design/semantics';
	import { sessionDisplayLabel } from './groupSessions';

	interface Props {
		session: SessionResponse;
		selected?: boolean;
		onclick?: () => void;
	}

	let { session, selected = false, onclick }: Props = $props();

	const status = $derived(coerceSessionStatus(String(session.status)));
	const color = $derived(sessionColor(status));
	const title = $derived(sessionDisplayLabel(session));
	const when = $derived(formatRelativeTime(session.last_seen_at));
</script>

<button type="button" class="card" class:selected {onclick} style:--accent={color}>
	<div class="top">
		<AgentIdentity name={session.agent_name} size="sm" />
		<span class="when">{when}</span>
	</div>
	<div class="label" title={title}>{title}</div>
	{#if session.status_text}
		<p class="status-text">{session.status_text}</p>
	{:else}
		<p class="status-text muted">No status text</p>
	{/if}
	<span class="status-pill" style:color={color}>{status}</span>
</button>

<style>
	.card {
		display: block;
		width: 100%;
		text-align: left;
		padding: 0.65rem 0.7rem;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		background: var(--hb-bg-elevated);
		cursor: pointer;
		box-shadow: inset 3px 0 0 var(--accent);
		transition: background 0.12s ease, border-color 0.12s ease;
	}
	.card:hover {
		background: var(--hb-bg-hover);
		border-color: color-mix(in srgb, var(--accent) 35%, var(--hb-border));
	}
	.card.selected {
		border-color: color-mix(in srgb, var(--accent) 55%, var(--hb-border));
		background: color-mix(in srgb, var(--accent) 8%, var(--hb-bg-elevated));
	}
	.top {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin-bottom: 0.35rem;
		min-width: 0;
	}
	.when {
		margin-left: auto;
		color: var(--hb-text-dim);
		font-size: 10px;
		flex-shrink: 0;
	}
	.label {
		font-weight: 650;
		font-size: 13px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		margin-bottom: 0.25rem;
	}
	.status-text {
		margin: 0 0 0.4rem;
		font-size: 12px;
		color: var(--hb-text-muted);
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
		overflow: hidden;
		line-height: 1.35;
	}
	.status-text.muted {
		color: var(--hb-text-dim);
		font-style: italic;
	}
	.status-pill {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
</style>
