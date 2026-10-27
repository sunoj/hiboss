<script lang="ts">
	import type { AgentResponse, Channel, CreateRoutingRuleRequest } from '$lib/api/types';
	import {
		DEFAULT_RULE_PRIORITY,
		ROUTING_CHANNELS,
		buildCreateRuleBody,
		isCreateRuleValid,
		type RuleFormValues
	} from './ruleForm';
	import { t } from '$lib/i18n';

	interface Props {
		agents: AgentResponse[];
		busy?: boolean;
		onCreate: (body: CreateRoutingRuleRequest) => void;
	}

	let { agents, busy = false, onCreate }: Props = $props();

	let open = $state(false);
	let ownerId = $state('');
	let channel = $state<Channel>('discord');
	let pattern = $state('');
	let targetId = $state('');
	let priority = $state(DEFAULT_RULE_PRIORITY);

	const formValues = $derived.by(
		(): RuleFormValues => ({
			owner_agent_id: ownerId,
			channel,
			pattern,
			target_agent_id: targetId,
			priority
		})
	);

	const canSubmit = $derived(isCreateRuleValid(formValues) && !busy && agents.length > 0);

	function reset() {
		ownerId = '';
		channel = 'discord';
		pattern = '';
		targetId = '';
		priority = DEFAULT_RULE_PRIORITY;
	}

	function submit(e: Event) {
		e.preventDefault();
		const body = buildCreateRuleBody(formValues);
		if (!body || busy) return;
		onCreate(body);
		reset();
		open = false;
	}
</script>

<div class="create">
	{#if !open}
		<button type="button" class="toggle" onclick={() => (open = true)} disabled={busy}>
			{t('form.addRule')}
		</button>
	{:else}
		<form class="form" onsubmit={submit}>
			<label>
				<span>{t('form.ownerAgent')}</span>
				<select bind:value={ownerId} required disabled={busy || agents.length === 0}>
				<option value="" disabled>{t('common.selectOwner')}</option>
					{#each agents as agent (agent.id)}
						<option value={agent.id}>{agent.name}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>{t('form.channel')}</span>
				<select bind:value={channel} disabled={busy}>
					{#each ROUTING_CHANNELS as ch (ch)}
						<option value={ch}>{ch}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>{t('form.pattern')}</span>
				<input
					bind:value={pattern}
					required
					placeholder={t('form.regexPattern')}
					disabled={busy}
					spellcheck="false"
				/>
			</label>
			<label>
				<span>{t('form.targetAgent')}</span>
				<select bind:value={targetId} required disabled={busy || agents.length === 0}>
				<option value="" disabled>{t('common.selectTarget')}</option>
					{#each agents as agent (agent.id)}
						<option value={agent.id}>{agent.name}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>{t('form.priority')}</span>
				<input
					type="number"
					bind:value={priority}
					disabled={busy}
					step="1"
				/>
			</label>
			<div class="actions">
				<button type="submit" class="primary" disabled={!canSubmit}>
					{busy ? t('common.creating') : t('form.createRule')}
				</button>
				<button
					type="button"
					class="ghost"
					disabled={busy}
					onclick={() => {
						open = false;
						reset();
					}}
				>
					{t('common.cancel')}
				</button>
			</div>
		</form>
		{#if agents.length === 0}
			<p class="hint">{t('form.noAgentsRule')}</p>
		{/if}
	{/if}
</div>

<style>
	@import '../../lib/design/create-form.css';
	.toggle,
	.actions button {
		font: inherit;
	}
	.toggle:hover:not(:disabled),
	.actions button:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.form {
		grid-template-columns: repeat(5, minmax(0, 1fr)) auto;
		box-shadow: var(--hb-shadow);
	}
	button:disabled,
	input:disabled,
	select:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}
	.hint {
		margin: 0.45rem 0 0;
		font-size: 11px;
		color: var(--hb-warning);
	}
	@media (max-width: 1100px) {
		.form {
			grid-template-columns: 1fr 1fr;
		}
		.actions {
			grid-column: 1 / -1;
		}
	}
</style>
