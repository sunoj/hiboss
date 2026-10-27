<script lang="ts">
	import type { AgentResponse, CreateGroupRequest } from '$lib/api/types';
	import { agentOptionLabel, canCreateGroup, sortAgentsByName } from './groupHelpers';
	import { t } from '$lib/i18n';

	interface Props {
		agents: AgentResponse[];
		busy?: boolean;
		onCreate: (body: CreateGroupRequest) => void;
	}

	let { agents, busy = false, onCreate }: Props = $props();

	let open = $state(false);
	let name = $state('');
	let description = $state('');
	let ownerAgentId = $state('');

	const sortedAgents = $derived(sortAgentsByName(agents));
	const ready = $derived(canCreateGroup(name, ownerAgentId));

	function submit(e: Event) {
		e.preventDefault();
		if (!ready || busy) return;
		const body: CreateGroupRequest = {
			name: name.trim(),
			owner_agent_id: ownerAgentId
		};
		const desc = description.trim();
		if (desc) body.description = desc;
		onCreate(body);
		name = '';
		description = '';
		ownerAgentId = '';
		open = false;
	}
</script>

<div class="create">
	{#if !open}
		<button type="button" class="toggle" onclick={() => (open = true)} disabled={busy}>
			{t('form.createGroup')}
		</button>
	{:else}
		<form class="form" onsubmit={submit}>
			<label>
				<span>{t('form.name')}</span>
				<input
					bind:value={name}
					required
					maxlength={80}
					placeholder={t('form.groupName')}
					disabled={busy}
				/>
			</label>
			<label>
				<span>{t('form.ownerAgent')}</span>
				<select bind:value={ownerAgentId} required disabled={busy || sortedAgents.length === 0}>
				<option value="">{t('common.selectOwner')}</option>
					{#each sortedAgents as agent (agent.id)}
						<option value={agent.id}>{agentOptionLabel(agent)}</option>
					{/each}
				</select>
			</label>
			<label class="desc">
				<span>{t('form.description')}</span>
				<input
					bind:value={description}
					maxlength={200}
					placeholder={t('common.optional')}
					disabled={busy}
				/>
			</label>
			<div class="actions">
				<button type="submit" class="primary" disabled={busy || !ready}>
					{busy ? t('common.creating') : t('common.create')}
				</button>
				<button type="button" class="ghost" disabled={busy} onclick={() => (open = false)}>
					{t('common.cancel')}
				</button>
			</div>
		</form>
		{#if sortedAgents.length === 0}
			<p class="hint" role="note">{t('form.noAgentsGroup')}</p>
		{/if}
	{/if}
</div>

<style>
	@import '../../lib/design/create-form.css';
	.toggle,
	.actions button {
		font: inherit;
		font-size: 12px;
	}
	.toggle:hover:not(:disabled),
	.actions button:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.form {
		grid-template-columns: minmax(0, 1.2fr) minmax(0, 1.4fr) minmax(0, 1.2fr) auto;
		box-shadow: var(--hb-shadow);
	}
	.hint {
		margin: 0.45rem 0 0;
		font-size: 11px;
		color: var(--hb-warning);
	}
	button:disabled {
		opacity: 0.55;
		cursor: wait;
	}
	@media (max-width: 900px) {
		.form {
			grid-template-columns: 1fr 1fr;
		}
		.desc,
		.actions {
			grid-column: 1 / -1;
		}
	}
</style>
