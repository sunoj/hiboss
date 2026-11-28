<script lang="ts">
	import type { AgentConfigResponse } from '$lib/api/types';
	import { apiErrorMessage } from '$lib/api/types';
	import { priorityLabel, PRIORITIES, type Priority } from '$lib/design/semantics';
	import { auth } from '$lib/stores/auth.svelte';
	import { toasts } from '$lib/stores/toast.svelte';
	import { t } from '$lib/i18n';
	import { buildConfigUpdate, defaultAgentConfig, rateLimitToInput } from './agent-helpers';

	interface Props {
		agentId: string;
		/** Session cache of last saved config for this agent, if any. */
		initial?: AgentConfigResponse | null;
		onSaved?: (config: AgentConfigResponse) => void;
	}

	let { agentId, initial = null, onSaved }: Props = $props();

	let priority = $state<Priority>('normal');
	let rateLimitRaw = $state('');
	let saving = $state(false);
	let baseline = $state<AgentConfigResponse>(defaultAgentConfig());
	const dirty = $derived(priority !== baseline.default_priority
		|| rateLimitRaw !== rateLimitToInput(baseline.rate_limit));

	function applyConfig(config: AgentConfigResponse) {
		baseline = config;
		priority = config.default_priority;
		rateLimitRaw = rateLimitToInput(config.rate_limit);
	}

	$effect(() => {
		void agentId;
		applyConfig(initial ?? defaultAgentConfig());
	});

	async function save() {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		const built = buildConfigUpdate({
			default_priority: priority,
			rateLimitRaw
		});
		if (!built.ok) {
			toasts.push(built.error, 'error');
			return;
		}
		if (saving || !dirty) return;
		saving = true;
		try {
			const updated = await client.updateAgentConfig(agentId, {
				...(built.body.default_priority !== baseline.default_priority
					? { default_priority: built.body.default_priority } : {}),
				...(built.body.rate_limit !== baseline.rate_limit ? { rate_limit: built.body.rate_limit } : {})
			});
			applyConfig(updated);
			onSaved?.(updated);
			toasts.push(t('form.agentConfigSaved'), 'success');
		} catch (e) {
			toasts.push(apiErrorMessage(e), 'error');
		} finally {
			saving = false;
		}
	}
</script>

<section class="config" aria-label={t('form.agentConfig')}>
	<h3>{t('form.config')}</h3>
	<p class="note">{t('form.configDetail')}</p>

	<div class="fields">
		<label class="field">
			<span class="label">{t('form.defaultPriority')}</span>
			<select bind:value={priority} disabled={saving}>
				{#each PRIORITIES as p (p)}
					<option value={p}>{priorityLabel(p)}</option>
				{/each}
			</select>
		</label>
		<label class="field">
			<span class="label">{t('form.rateLimit')}</span>
			<input
				type="text"
				inputmode="numeric"
				placeholder={t('common.noLimit')}
				bind:value={rateLimitRaw}
				disabled={saving}
			/>
		</label>
	</div>

	<button type="button" class="save" disabled={saving || !dirty} onclick={() => void save()}>
		{saving ? t('common.saving') : t('form.saveConfig')}
	</button>
</section>

<style>
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
	.label {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-dim);
	}
	.field input,
	.field select {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-input);
		border-radius: var(--hb-radius-sm);
		padding: 0.4rem 0.55rem;
		color: var(--hb-text);
		font: inherit;
		font-size: 12px;
	}
	.field input:disabled,
	.field select:disabled {
		opacity: 0.65;
		cursor: wait;
	}
	.save {
		width: 100%;
		border: 1px solid color-mix(in srgb, var(--hb-accent) 40%, var(--hb-border));
		background: color-mix(in srgb, var(--hb-accent) 22%, var(--hb-bg-elevated));
		color: var(--hb-text);
		border-radius: var(--hb-radius-sm);
		padding: 0.45rem 0.7rem;
		cursor: pointer;
		font-weight: 600;
		font-size: 12px;
	}
	.save:hover:not(:disabled) {
		background: color-mix(in srgb, var(--hb-accent) 32%, var(--hb-bg-elevated));
	}
	.save:disabled {
		opacity: 0.65;
		cursor: wait;
	}
	@media (max-width: 720px) {
		.fields {
			grid-template-columns: 1fr;
		}
	}
</style>
