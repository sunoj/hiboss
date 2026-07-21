<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AgentResponse } from '$lib/api/types';
	import { lastUsedLabel, roleLabel } from './agent-helpers';

	interface Props {
		agents: AgentResponse[];
		selectedId: string | null;
		onSelect: (agent: AgentResponse) => void;
	}

	let { agents, selectedId, onSelect }: Props = $props();
</script>

<div class="wrap">
	<table class="table">
		<thead>
			<tr>
				<th scope="col">Agent</th>
				<th scope="col">Role</th>
				<th scope="col">Last used</th>
				<th scope="col" class="right">Created</th>
			</tr>
		</thead>
		<tbody>
			{#each agents as agent (agent.id)}
				<tr
					class:selected={selectedId === agent.id}
					onclick={() => onSelect(agent)}
					onkeydown={(e) => {
						if (e.key === 'Enter' || e.key === ' ') {
							e.preventDefault();
							onSelect(agent);
						}
					}}
					tabindex="0"
					role="button"
					aria-pressed={selectedId === agent.id}
				>
					<td>
						<AgentIdentity name={agent.name} size="sm" />
					</td>
					<td class="muted">{roleLabel(agent.role)}</td>
					<td class="muted">{lastUsedLabel(agent.last_used_at)}</td>
					<td class="muted right">{formatRelativeTime(agent.created_at)}</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>

<style>
	.wrap {
		overflow-x: auto;
	}
	.table {
		width: 100%;
		border-collapse: collapse;
		font-size: 13px;
	}
	th {
		text-align: left;
		padding: 0.65rem 1rem;
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
		color: var(--hb-text-muted);
		border-bottom: 1px solid var(--hb-border-subtle);
		background: var(--hb-bg-elevated);
		white-space: nowrap;
	}
	th.right,
	td.right {
		text-align: right;
	}
	td {
		padding: 0.7rem 1rem;
		border-bottom: 1px solid var(--hb-border-subtle);
		vertical-align: middle;
	}
	tbody tr {
		cursor: pointer;
		transition: background 0.12s ease;
	}
	tbody tr:hover {
		background: var(--hb-bg-hover);
	}
	tbody tr.selected {
		background: color-mix(in srgb, var(--hb-accent) 12%, var(--hb-bg-panel));
	}
	tbody tr:focus-visible {
		outline: 2px solid var(--hb-accent);
		outline-offset: -2px;
	}
	.muted {
		color: var(--hb-text-muted);
		font-size: 12px;
	}
</style>
