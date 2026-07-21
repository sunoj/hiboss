<script lang="ts">
	import type { AgentResponse, Channel, CreateRoutingRuleRequest } from '$lib/api/types';
	import {
		DEFAULT_RULE_PRIORITY,
		ROUTING_CHANNELS,
		buildCreateRuleBody,
		isCreateRuleValid,
		type RuleFormValues
	} from './ruleForm';

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
			Add rule
		</button>
	{:else}
		<form class="form" onsubmit={submit}>
			<label>
				<span>Owner agent</span>
				<select bind:value={ownerId} required disabled={busy || agents.length === 0}>
					<option value="" disabled>Select owner</option>
					{#each agents as agent (agent.id)}
						<option value={agent.id}>{agent.name}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>Channel</span>
				<select bind:value={channel} disabled={busy}>
					{#each ROUTING_CHANNELS as ch (ch)}
						<option value={ch}>{ch}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>Pattern</span>
				<input
					bind:value={pattern}
					required
					placeholder="regex pattern"
					disabled={busy}
					spellcheck="false"
				/>
			</label>
			<label>
				<span>Target agent</span>
				<select bind:value={targetId} required disabled={busy || agents.length === 0}>
					<option value="" disabled>Select target</option>
					{#each agents as agent (agent.id)}
						<option value={agent.id}>{agent.name}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>Priority</span>
				<input
					type="number"
					bind:value={priority}
					disabled={busy}
					step="1"
				/>
			</label>
			<div class="actions">
				<button type="submit" class="primary" disabled={!canSubmit}>
					{busy ? 'Creating…' : 'Create'}
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
					Cancel
				</button>
			</div>
		</form>
		{#if agents.length === 0}
			<p class="hint">No agents available — grant access before adding rules.</p>
		{/if}
	{/if}
</div>

<style>
	.create {
		margin-bottom: 0.75rem;
	}
	.toggle,
	.actions button {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-panel);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.7rem;
		cursor: pointer;
		color: var(--hb-text);
		font: inherit;
	}
	.toggle:hover:not(:disabled),
	.actions button:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.form {
		display: grid;
		grid-template-columns: repeat(5, minmax(0, 1fr)) auto;
		gap: 0.55rem;
		align-items: end;
		padding: 0.75rem;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		background: var(--hb-bg-panel);
		box-shadow: var(--hb-shadow);
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--hb-text-muted);
	}
	input,
	select {
		font: inherit;
		font-size: 12px;
		font-weight: 500;
		text-transform: none;
		letter-spacing: normal;
		padding: 0.4rem 0.5rem;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-input);
		color: var(--hb-text);
	}
	.actions {
		display: flex;
		gap: 0.35rem;
	}
	.primary {
		background: color-mix(in srgb, var(--hb-accent) 22%, var(--hb-bg-elevated));
		border-color: color-mix(in srgb, var(--hb-accent) 40%, var(--hb-border));
	}
	.ghost {
		background: transparent;
		color: var(--hb-text-muted);
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
