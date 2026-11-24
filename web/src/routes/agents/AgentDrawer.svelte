<!-- Agent detail drawer with profile, config and credential management.
     Depends on agent metadata, auth and the console detail components. -->
<script lang="ts">
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AgentConfigResponse, AgentResponse } from '$lib/api/types';
	import { lastUsedLabel, roleLabel, shortId } from './agent-helpers';
	import AgentConfigForm from './AgentConfigForm.svelte';
	import AgentKeys from './AgentKeys.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';

	interface Props {
		agent: AgentResponse;
		config?: AgentConfigResponse | null;
		onConfigSaved?: (agentId: string, config: AgentConfigResponse) => void;
	}

	let { agent, config = null, onConfigSaved }: Props = $props();
</script>

<div class="panel">
	<header class="head">
		<div class="titles">
			<h1>{agent.name}</h1>
		</div>
		<a href="/agents">← {t('nav.agents')}</a>
	</header>

	<div class="body">
		<section class="meta">
			<div class="row">
				<span class="k">{t('form.id')}</span>
				<span class="mono" title={agent.id}>{shortId(agent.id)}</span>
			</div>
			<div class="row">
				<span class="k">{t('form.role')}</span>
				<span>{roleLabel(agent.role)}</span>
			</div>
			<div class="row">
				<span class="k">{t('form.lastSeen')}</span>
				<span>{lastUsedLabel(agent.last_used_at)}</span>
			</div>
			<div class="row">
				<span class="k">{t('form.created')}</span>
				<span>{formatRelativeTime(agent.created_at)}</span>
			</div>
		</section>

		{#if auth.connection?.boss?.role === 'admin' || auth.connection?.boss?.role === 'manager'}
			{#key agent.id}<AgentKeys agentId={agent.id} />{/key}
		{/if}
		{#if auth.connection?.boss?.role !== 'viewer'}
		<AgentConfigForm
			agentId={agent.id}
			initial={config}
			onSaved={(next) => onConfigSaved?.(agent.id, next)}
		/>
		{/if}
	</div>
</div>

<style>
	.panel { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-m);
		padding: 16px; margin-bottom: 16px; overflow-wrap: anywhere; }
	.head { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 8px; }
	h1 { font: var(--t-title); margin: 0; }
	a { color: var(--live); text-decoration: underline; }
	.body { display: grid; gap: 16px; min-width: 0; }
	.meta { padding-block-start: 12px; }
	.row { display: flex; gap: 8px; }
	.k { font: var(--t-caption); color: var(--text-3); }
</style>
