<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AgentResponse } from '$lib/api/types';
	import { lastUsedLabel, roleLabel, shortId } from './agent-helpers';

	interface Props {
		agent: AgentResponse;
		onClose: () => void;
	}

	let { agent, onClose }: Props = $props();
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

		<section class="config">
			<h3>Config</h3>
			<p class="note">
				Boss-scoped agent config is read-only — writing default priority, rate limit, and
				channel routing needs a boss-scoped write endpoint.
			</p>

			<div class="fields">
				<label class="field">
					<span class="label">Default priority</span>
					<input type="text" value="—" disabled readonly />
				</label>
				<label class="field">
					<span class="label">Rate limit</span>
					<input type="text" value="—" disabled readonly />
				</label>
				<label class="field wide">
					<span class="label">Channel routing</span>
					<input type="text" value="—" disabled readonly />
				</label>
			</div>

			<button
				type="button"
				class="edit"
				disabled
				title="needs a boss-scoped write endpoint"
			>
				Edit config…
			</button>
			<p class="hint">needs a boss-scoped write endpoint</p>
		</section>
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
	h3 {
		margin: 0 0 0.45rem;
		font-size: 11px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.note {
		margin: 0 0 0.75rem;
		font-size: 11px;
		color: var(--hb-text-dim);
		line-height: 1.4;
	}
	.fields {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.65rem;
		margin-bottom: 0.75rem;
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		min-width: 0;
	}
	.field.wide {
		grid-column: 1 / -1;
	}
	.label {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-dim);
	}
	.field input {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-input);
		border-radius: var(--hb-radius-sm);
		padding: 0.4rem 0.55rem;
		color: var(--hb-text-dim);
		font: inherit;
		font-size: 12px;
		cursor: not-allowed;
		opacity: 0.75;
	}
	.edit {
		width: 100%;
		border: 1px dashed var(--hb-border);
		background: var(--hb-bg-input);
		border-radius: var(--hb-radius-sm);
		padding: 0.45rem 0.7rem;
		color: var(--hb-text-dim);
		cursor: not-allowed;
		opacity: 0.7;
	}
	.hint {
		margin: 0.4rem 0 0;
		font-size: 11px;
		color: var(--hb-text-dim);
		line-height: 1.35;
	}
	@media (max-width: 720px) {
		.fields {
			grid-template-columns: 1fr;
		}
	}
</style>
