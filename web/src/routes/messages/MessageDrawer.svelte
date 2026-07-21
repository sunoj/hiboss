<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import StatusBadges from '$lib/components/StatusBadges.svelte';
	import { extractOptions } from '$lib/api/mappers';
	import type { MessageResponse } from '$lib/api/types';
	import { formatAbsoluteTime, sessionTitle } from './message-helpers';
	import MessageDrawerActions from './MessageDrawerActions.svelte';

	interface Props {
		message: MessageResponse;
		onClose: () => void;
		onUpdated?: (message: MessageResponse) => void;
	}

	let { message, onClose, onUpdated }: Props = $props();

	const options = $derived(extractOptions(message.metadata));
	const expired = $derived(Boolean(message.metadata?.options_expired));

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') onClose();
	}
</script>

<svelte:window onkeydown={onKeydown} />

<button type="button" class="backdrop" aria-label="Close drawer" onclick={onClose}></button>

<div class="drawer" role="dialog" aria-modal="true" aria-label="Message detail">
	<header class="head">
		<div>
			<h2>Message detail</h2>
			<p class="id" title={message.id}>{message.id}</p>
		</div>
		<button type="button" class="close" onclick={onClose} aria-label="Close">×</button>
	</header>

	<div class="body">
		<div class="identity">
			<AgentIdentity name={message.agent_name} size="md" />
			<span class="session">{sessionTitle(message)}</span>
		</div>

		<StatusBadges
			priority={message.priority}
			direction={message.direction}
			status={message.status}
		/>

		{#if message.mode === 'blocking'}
			<span class="blocking">blocking</span>
		{/if}

		<div class="times">
			<div><span class="k">Created</span> {formatAbsoluteTime(message.created_at)}</div>
			<div><span class="k">Updated</span> {formatAbsoluteTime(message.updated_at)}</div>
			{#if message.expires_at}
				<div><span class="k">Expires</span> {formatAbsoluteTime(message.expires_at)}</div>
			{/if}
			{#if message.channel}
				<div><span class="k">Channel</span> {message.channel}</div>
			{/if}
		</div>

		<pre class="content">{message.body}</pre>

		<MessageDrawerActions
			messageId={message.id}
			{options}
			optionsExpired={expired}
			{onUpdated}
		/>
	</div>
</div>

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		background: color-mix(in srgb, var(--hb-bg) 55%, transparent);
		z-index: 40;
		border: none;
		padding: 0;
		cursor: pointer;
	}
	.drawer {
		position: fixed;
		top: 0;
		right: 0;
		bottom: 0;
		width: min(420px, 100vw);
		z-index: 50;
		background: var(--hb-bg-panel);
		border-left: 1px solid var(--hb-border);
		box-shadow: var(--hb-shadow);
		display: flex;
		flex-direction: column;
		overflow: hidden;
	}
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 0.75rem;
		padding: 0.9rem 1rem;
		border-bottom: 1px solid var(--hb-border-subtle);
	}
	h2 {
		margin: 0;
		font-size: 0.95rem;
		font-weight: 700;
	}
	.id {
		margin: 0.2rem 0 0;
		font-family: var(--hb-font-mono);
		font-size: 11px;
		color: var(--hb-text-dim);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		max-width: 280px;
	}
	.close {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		width: 2rem;
		height: 2rem;
		font-size: 1.25rem;
		line-height: 1;
		cursor: pointer;
		color: var(--hb-text-muted);
	}
	.body {
		padding: 1rem;
		overflow: auto;
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}
	.identity {
		display: flex;
		align-items: center;
		gap: 0.65rem;
		flex-wrap: wrap;
	}
	.session {
		font-family: var(--hb-font-mono);
		font-size: 11px;
		color: var(--hb-text-muted);
	}
	.blocking {
		align-self: flex-start;
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		color: var(--hb-warning);
	}
	.times {
		display: grid;
		gap: 0.25rem;
		font-size: 12px;
		color: var(--hb-text-muted);
	}
	.k {
		display: inline-block;
		min-width: 4.2rem;
		color: var(--hb-text-dim);
		font-weight: 600;
		text-transform: uppercase;
		font-size: 10px;
		letter-spacing: 0.04em;
	}
	.content {
		margin: 0;
		padding: 0.75rem;
		background: var(--hb-bg-input);
		border: 1px solid var(--hb-border-subtle);
		border-radius: var(--hb-radius);
		white-space: pre-wrap;
		word-break: break-word;
		font-family: var(--hb-font);
		font-size: 13px;
		line-height: 1.45;
		color: var(--hb-text);
	}
</style>
