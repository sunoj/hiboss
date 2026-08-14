<script lang="ts">
	import AgentIdentity from './AgentIdentity.svelte';
	import StatusBadges from './StatusBadges.svelte';
	import { extractOptions, formatRelativeTime, truncateBody } from '$lib/api/mappers';
	import type { MessageResponse } from '$lib/api/types';
	import { t } from '$lib/i18n';

	interface Props {
		message: MessageResponse;
	}

	let { message }: Props = $props();

	const options = $derived(extractOptions(message.metadata));
	const when = $derived(formatRelativeTime(message.created_at));
</script>

<article class="row" class:blocking={message.mode === 'blocking'}>
	<div class="meta">
		<AgentIdentity name={message.agent_name} />
		{#if message.session_label}
			<span class="session" title={message.session_branch ?? ''}>{message.session_label}</span>
		{/if}
		<span class="time">{when}</span>
	</div>
	<p class="body">{truncateBody(message.body, 160)}</p>
	<div class="footer">
		<StatusBadges
			priority={message.priority}
			direction={message.direction}
			status={message.status}
			compact
		/>
		{#if message.mode === 'blocking'}
			<span class="blocking-tag">{t('status.blocking')}</span>
		{/if}
	</div>
	{#if options.length > 0}
		<div class="options" role="group" aria-label={t('form.messageOptions')}>
			{#each options as option (option)}
				<button type="button" class="option" disabled>{option}</button>
			{/each}
		</div>
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
	.row.blocking {
		box-shadow: inset 3px 0 0 var(--hb-warning);
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
	.footer {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		flex-wrap: wrap;
	}
	.blocking-tag {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		color: var(--hb-warning);
	}
	.options {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
		margin-top: 0.55rem;
	}
	.option {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.25rem 0.55rem;
		cursor: default;
		opacity: 0.85;
	}
</style>
