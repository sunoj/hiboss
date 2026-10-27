<!-- Agent detail drawer with profile, config and credential management.
     Depends on agent metadata, auth and the console detail components. -->
<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
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
		onClose: () => void;
		onConfigSaved?: (agentId: string, config: AgentConfigResponse) => void;
	}

	let { agent, config = null, onClose, onConfigSaved }: Props = $props();
</script>

<div class="drawer" role="dialog" aria-modal="true" aria-label={t('form.agentDetail')}>
	<header class="head">
		<div class="titles">
			<h2>{t('nav.agents')}</h2>
			<AgentIdentity name={agent.name} size="md" />
		</div>
		<button type="button" class="close" onclick={onClose} aria-label={t('common.close')}>✕</button>
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
		<AgentConfigForm
			agentId={agent.id}
			initial={config}
			onSaved={(next) => onConfigSaved?.(agent.id, next)}
		/>
	</div>
</div>

<style>
	@import '../../lib/design/detail-drawer.css';
	.titles {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}
	h2 {
		margin: 0;
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.body {
		gap: 1rem;
	}
	.k {
		font-size: 11px;
		letter-spacing: 0.04em;
	}
	.mono {
		font-size: 11px;
	}
</style>
