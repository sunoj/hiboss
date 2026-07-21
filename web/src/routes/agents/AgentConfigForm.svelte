<script lang="ts">
	import type { AgentConfigResponse } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { PRIORITIES, type Priority } from '$lib/design/semantics';
	import { auth } from '$lib/stores/auth.svelte';
	import { toasts } from '$lib/stores/toast.svelte';
	import {
		AGENT_CHANNELS,
		buildConfigUpdate,
		defaultAgentConfig,
		isAgentChannel,
		rateLimitToInput,
		routingEntriesFromMap,
		type RoutingEntry
	} from './agent-helpers';

	interface Props {
		agentId: string;
		/** Session cache of last saved config for this agent, if any. */
		initial?: AgentConfigResponse | null;
		onSaved?: (config: AgentConfigResponse) => void;
	}

	let { agentId, initial = null, onSaved }: Props = $props();

	let priority = $state<Priority>('normal');
	let rateLimitRaw = $state('');
	let routing = $state<RoutingEntry[]>([]);
	let saving = $state(false);

	function applyConfig(config: AgentConfigResponse) {
		priority = config.default_priority;
		rateLimitRaw = rateLimitToInput(config.rate_limit);
		routing = routingEntriesFromMap(config.channel_routing);
	}

	$effect(() => {
		void agentId;
		applyConfig(initial ?? defaultAgentConfig());
	});

	function addRoute() {
		routing = [...routing, { key: '', channel: 'discord' }];
	}

	function removeRoute(index: number) {
		routing = routing.filter((_, i) => i !== index);
	}

	function setRouteKey(index: number, key: string) {
		routing = routing.map((row, i) => (i === index ? { ...row, key } : row));
	}

	function setRouteChannel(index: number, value: string) {
		if (!isAgentChannel(value)) return;
		routing = routing.map((row, i) => (i === index ? { ...row, channel: value } : row));
	}

	function errMsg(e: unknown): string {
		return e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
	}

	async function save() {
		const client = auth.client;
		if (!client) {
			toasts.push('Not connected', 'error');
			return;
		}
		const built = buildConfigUpdate({
			default_priority: priority,
			rateLimitRaw,
			routing
		});
		if (!built.ok) {
			toasts.push(built.error, 'error');
			return;
		}
		if (saving) return;
		saving = true;
		try {
			const updated = await client.updateAgentConfig(agentId, built.body);
			applyConfig(updated);
			onSaved?.(updated);
			toasts.push('Agent config saved', 'success');
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			saving = false;
		}
	}
</script>

<section class="config" aria-label="Agent config">
	<h3>Config</h3>
	<p class="note">Default priority, rate limit, and channel routing for this agent.</p>

	<div class="fields">
		<label class="field">
			<span class="label">Default priority</span>
			<select bind:value={priority} disabled={saving}>
				{#each PRIORITIES as p (p)}
					<option value={p}>{p}</option>
				{/each}
			</select>
		</label>
		<label class="field">
			<span class="label">Rate limit</span>
			<input
				type="text"
				inputmode="numeric"
				placeholder="No limit"
				bind:value={rateLimitRaw}
				disabled={saving}
			/>
		</label>
		<div class="field wide">
			<span class="label">Channel routing</span>
			{#if routing.length === 0}
				<p class="empty-routes">No routes — keys map to a channel (e.g. critical → discord).</p>
			{:else}
				<ul class="routes">
					{#each routing as row, i (i)}
						<li class="route">
							<input
								type="text"
								placeholder="key"
								value={row.key}
								disabled={saving}
								oninput={(e) => setRouteKey(i, e.currentTarget.value)}
							/>
							<select
								value={row.channel}
								disabled={saving}
								onchange={(e) => setRouteChannel(i, e.currentTarget.value)}
							>
								{#each AGENT_CHANNELS as ch (ch)}
									<option value={ch}>{ch}</option>
								{/each}
							</select>
							<button
								type="button"
								class="ghost"
								disabled={saving}
								onclick={() => removeRoute(i)}
								aria-label="Remove route"
							>
								✕
							</button>
						</li>
					{/each}
				</ul>
			{/if}
			<button type="button" class="ghost add" disabled={saving} onclick={addRoute}>
				Add route
			</button>
		</div>
	</div>

	<button type="button" class="save" disabled={saving} onclick={() => void save()}>
		{saving ? 'Saving…' : 'Save config'}
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
	.field input,
	.field select,
	.route input,
	.route select {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-input);
		border-radius: var(--hb-radius-sm);
		padding: 0.4rem 0.55rem;
		color: var(--hb-text);
		font: inherit;
		font-size: 12px;
	}
	.field input:disabled,
	.field select:disabled,
	.route input:disabled,
	.route select:disabled {
		opacity: 0.65;
		cursor: wait;
	}
	.empty-routes {
		margin: 0;
		font-size: 11px;
		color: var(--hb-text-dim);
		line-height: 1.35;
	}
	.routes {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	.route {
		display: grid;
		grid-template-columns: 1fr 1fr auto;
		gap: 0.35rem;
		align-items: center;
	}
	.ghost {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.55rem;
		color: var(--hb-text-muted);
		cursor: pointer;
		font-size: 12px;
	}
	.ghost:hover:not(:disabled) {
		background: var(--hb-bg-hover);
		color: var(--hb-text);
	}
	.ghost:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}
	.add {
		margin-top: 0.4rem;
		align-self: start;
		width: fit-content;
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
		.route {
			grid-template-columns: 1fr;
		}
	}
</style>
