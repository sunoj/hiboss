<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AgentConfigResponse, AgentResponse } from '$lib/api/types';
	import { lastUsedLabel, roleLabel, shortId } from './agent-helpers';
	import AgentConfigForm from './AgentConfigForm.svelte';

	interface Props {
		agent: AgentResponse;
		config?: AgentConfigResponse | null;
		onClose: () => void;
		onConfigSaved?: (agentId: string, config: AgentConfigResponse) => void;
	}

	let { agent, config = null, onClose, onConfigSaved }: Props = $props();
</script>

<div class="drawer" role="dialog" aria-modal="true" aria-label="Agent detail">
	<header class="head">
		<div class="titles">
			<h2>Agent</h2>
			<AgentIdentity name={agent.name} size="md" />
		</div>
		<button type="button" class="close" onclick={onClose} aria-label="Close">✕</button>
	</header>

	<div class="body">
		<section class="meta">
			<div class="row">
				<span class="k">Id</span>
				<span class="mono" title={agent.id}>{shortId(agent.id)}</span>
			</div>
			<div class="row">
				<span class="k">Role</span>
				<span>{roleLabel(agent.role)}</span>
			</div>
			<div class="row">
				<span class="k">Last used</span>
				<span>{lastUsedLabel(agent.last_used_at)}</span>
			</div>
			<div class="row">
				<span class="k">Created</span>
				<span>{formatRelativeTime(agent.created_at)}</span>
			</div>
		</section>

		<AgentConfigForm
			agentId={agent.id}
			initial={config}
			onSaved={(next) => onConfigSaved?.(agent.id, next)}
		/>
	</div>
</div>

<style>
	.drawer {
		display: flex;
		flex-direction: column;
		width: min(380px, 100%);
		height: 100%;
		background: var(--hb-bg-panel);
		border-left: 1px solid var(--hb-border);
		box-shadow: var(--hb-shadow);
	}
	.head {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		padding: 0.85rem 1rem;
		border-bottom: 1px solid var(--hb-border-subtle);
	}
	.titles {
		min-width: 0;
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	h2 {
		margin: 0;
		font-size: 11px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.close {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		width: 1.75rem;
		height: 1.75rem;
		cursor: pointer;
		flex-shrink: 0;
	}
	.body {
		flex: 1;
		overflow-y: auto;
		padding: 0.85rem 1rem 1.25rem;
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	.meta .row {
		display: grid;
		grid-template-columns: 5rem 1fr;
		gap: 0.5rem;
		align-items: center;
		margin-bottom: 0.4rem;
		font-size: 12px;
	}
	.k {
		color: var(--hb-text-dim);
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.mono {
		font-family: var(--hb-font-mono);
		font-size: 11px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
</style>
