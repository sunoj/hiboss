<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import type { AgentResponse } from '$lib/api/types';
	import { agentOptionLabel, sortAgentsByName } from './groupHelpers';
	import { t } from '$lib/i18n';

	interface Props {
		agents: AgentResponse[];
		busy?: boolean;
		onAdd: (agentId: string) => void;
		onRemove: (agentId: string) => void;
		onClose: () => void;
	}

	let { agents, busy = false, onAdd, onRemove, onClose }: Props = $props();

	let selectedId = $state('');
	const sorted = $derived(sortAgentsByName(agents));
	const selected = $derived(sorted.find((a) => a.id === selectedId) ?? null);

	function add() {
		if (!selectedId || busy) return;
		onAdd(selectedId);
	}

	function remove() {
		if (!selectedId || busy) return;
		onRemove(selectedId);
	}
</script>

<div class="editor" role="region" aria-label={t('form.memberEditor')}>
	<div class="head">
		<span class="title">{t('form.members')}</span>
		<button type="button" class="ghost" onclick={onClose} disabled={busy}>{t('common.close')}</button>
	</div>

	{#if sorted.length === 0}
		<p class="empty">{t('page.noAgentsInScope')}</p>
	{:else}
		<label class="field">
			<span>{t('nav.agents')}</span>
			<select bind:value={selectedId} disabled={busy}>
				<option value="">{t('common.selectAgent')}</option>
				{#each sorted as agent (agent.id)}
					<option value={agent.id}>{agentOptionLabel(agent)}</option>
				{/each}
			</select>
		</label>

		{#if selected}
			<div class="preview">
				<AgentIdentity name={selected.name} size="sm" />
			</div>
		{/if}

		<div class="actions">
			<button type="button" class="btn" disabled={busy || !selectedId} onclick={add}>
				{t('form.addMember')}
			</button>
			<button type="button" class="btn danger" disabled={busy || !selectedId} onclick={remove}>
				{t('form.removeMember')}
			</button>
		</div>
	{/if}
</div>

<style>
	.editor {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-top: 0.35rem;
		padding: 0.65rem 0.7rem;
		border: 1px solid var(--hb-border-subtle);
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-elevated);
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
	}
	.title {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--hb-text-muted);
	}
	select {
		font: inherit;
		font-size: 12px;
		font-weight: 500;
		text-transform: none;
		letter-spacing: normal;
		padding: 0.35rem 0.45rem;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-input);
		color: var(--hb-text);
	}
	.preview {
		font-size: 12px;
	}
	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
	}
	.btn,
	.ghost {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-panel);
		border-radius: var(--hb-radius-sm);
		padding: 0.28rem 0.55rem;
		font: inherit;
		font-size: 11px;
		color: var(--hb-text);
		cursor: pointer;
	}
	.btn:hover:not(:disabled),
	.ghost:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.btn.danger {
		border-color: color-mix(in srgb, var(--hb-danger) 40%, var(--hb-border));
		color: var(--hb-danger);
	}
	.ghost {
		background: transparent;
		color: var(--hb-text-muted);
		padding: 0.15rem 0.4rem;
	}
	.empty {
		margin: 0;
		font-size: 11px;
		color: var(--hb-text-dim);
	}
	button:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}
</style>
