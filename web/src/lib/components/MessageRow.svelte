<script lang="ts">
	import { agentDirectory } from '$lib/stores/agents.svelte';
	import { isIntegrationMessage } from '$lib/api/agent-capabilities';
	import AgentIdentity from './AgentIdentity.svelte';
	import { formatRelativeTime, truncateBody } from '$lib/api/mappers';
	import type { MessageResponse } from '$lib/api/types';
	import { formatDateTime, t } from '$lib/i18n';

	interface Props {
		message: MessageResponse;
	}

	let { message }: Props = $props();

	const when = $derived(formatRelativeTime(message.created_at));
</script>

<article class="row" aria-label={message.body}>
	<div class="meta">
		<AgentIdentity name={message.agent_name} />
		{#if message.session_label}
			<span class="session" title={message.session_branch ?? ''}>{message.session_label}</span>
		{/if}
		<time class="time" datetime={message.created_at} title={formatDateTime(message.created_at)}>{when}</time>
	</div>
	<p class="body">{truncateBody(message.body, 160)}</p>
	{#if isIntegrationMessage(message, agentDirectory.rows)}
		<span class="badge">{t('console.integration')}</span>
	{:else if message.direction === 'agent_to_agent'}
		<span class="badge">{t('console.peer')}</span>
	{/if}
</article>

<style>
	.row {
		padding: 0.7rem 0.85rem;
		border-bottom: 1px solid var(--hb-border-subtle);
		background: var(--hb-bg-panel);
	}
	.row:hover {
		background: var(--hb-bg-hover);
	}
	.meta {
		display: flex;
		align-items: center;
		gap: 0.55rem;
		margin-bottom: 0.3rem;
		min-width: 0;
	}
	.session {
		color: var(--hb-text-muted);
		font-family: var(--hb-font-mono);
		font-size: 11px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.time {
		margin-left: auto;
		color: var(--hb-text-dim);
		font-size: 11px;
		flex-shrink: 0;
	}
	.body {
		margin: 0 0 0.4rem;
		color: var(--hb-text);
		white-space: pre-wrap;
		word-break: break-word;
	}
	.badge { font: var(--t-caption); background: var(--neutral-soft); border-radius: var(--r-pill);
		padding: 3px 8px; color: var(--text-2); }
</style>
