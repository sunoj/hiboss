<!-- Agent detail drawer with profile, config and credential management.
     Depends on agent metadata, auth and the console detail components. -->
<script lang="ts">
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AgentResponse } from '$lib/api/types';
	import { agentConfig, lastUsedLabel, roleLabel, shortId } from './agent-helpers';
	import AgentConfigForm from './AgentConfigForm.svelte';
	import AgentKeys from './AgentKeys.svelte';
	import AgentAdminSwitch from './AgentAdminSwitch.svelte';
	import { canSetAgentAdmin } from '$lib/api/agent-capabilities';
	import { agentDirectory } from '$lib/stores/agents.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';

	let { agent }: { agent: AgentResponse } = $props();
	const config = $derived(agentConfig(agent));
	const role = $derived(auth.connection?.boss?.role);

</script>

<div class="panel">
	<header class="head">
		<div class="titles">
			<h1>{agent.name}</h1>
			{#if agent.kind === 'integration'}<span class="badge live">{t('console.integration')}</span>{/if}
			{#if agent.admin}<span class="badge settled">{t('console.adminCapability')}</span>{/if}
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

		{#if canSetAgentAdmin(agent, role)}<AgentAdminSwitch {agent} />{/if}
		{#if agent.kind === 'integration'}
			<p>{t('console.webhookKeys')}</p>
		{:else if role === 'admin' || (role === 'manager' && !agent.admin)}
			<AgentKeys agentId={agent.id} />
		{:else if role === 'manager' && agent.admin}
			<p>{t('console.adminKeys')}</p>
		{/if}
		{#if role !== 'viewer'}
		<AgentConfigForm
			agentId={agent.id}
			initial={config}
			onSaved={(next) => { if (auth.client) agentDirectory.update(auth.client, agent.id, next); }}
		/>
		{/if}
	</div>
</div>

<style>
	.panel { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-m);
		padding: 16px; margin-bottom: 16px; overflow-wrap: anywhere; }
	.head { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 8px; }
	h1 { font: var(--t-large); margin: 0; }
	a { color: var(--live); text-decoration: underline; }
	.body { display: grid; gap: 16px; min-width: 0; }
	.meta { padding-block-start: 12px; }
	.row { display: flex; gap: 8px; }
	.k { font: var(--t-caption); color: var(--text-3); }
</style>
