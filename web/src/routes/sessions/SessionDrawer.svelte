<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import StatusBadges from '$lib/components/StatusBadges.svelte';
	import { formatRelativeTime, truncateBody } from '$lib/api/mappers';
	import type { MessageResponse, SessionResponse } from '$lib/api/types';
	import { coerceSessionStatus, sessionColor } from '$lib/design/semantics';
	import { sessionDisplayLabel, shortId } from './groupSessions';
	import { t } from '$lib/i18n';

	interface Props {
		session: SessionResponse;
		messages: MessageResponse[];
		loading: boolean;
		error: string | null;
		onClose: () => void;
		onRetry: () => void;
	}

	let { session, messages, loading, error, onClose, onRetry }: Props = $props();

	const status = $derived(coerceSessionStatus(String(session.status)));
	const color = $derived(sessionColor(status));
	const title = $derived(sessionDisplayLabel(session));
</script>

<div class="drawer" role="dialog" aria-modal="true" aria-label={t('form.sessionDetail')}>
	<header class="head">
		<div class="titles">
			<span class="pill" style:color={color}>{status}</span>
			<h2 title={title}>{title}</h2>
		</div>
		<button type="button" class="close" onclick={onClose} aria-label={t('common.close')}>✕</button>
	</header>

	<div class="body">
		<section class="meta">
			<div class="row">
				<span class="k">{t('nav.agents')}</span>
				<AgentIdentity name={session.agent_name} size="md" />
			</div>
			<div class="row">
				<span class="k">{t('form.id')}</span>
				<span class="mono" title={session.id}>{shortId(session.id)}</span>
			</div>
			{#if session.branch}
				<div class="row">
					<span class="k">{t('form.branch')}</span>
					<span class="mono">{session.branch}</span>
				</div>
			{/if}
			{#if session.cwd}
				<div class="row">
					<span class="k">{t('form.cwd')}</span>
					<span class="mono path">{session.cwd}</span>
				</div>
			{/if}
			<div class="row">
				<span class="k">{t('form.lastSeen')}</span>
				<span>{formatRelativeTime(session.last_seen_at)}</span>
			</div>
			{#if session.started_at}
				<div class="row">
					<span class="k">{t('form.started')}</span>
					<span>{formatRelativeTime(session.started_at)}</span>
				</div>
			{/if}
			{#if session.status_text}
				<p class="status-text">{session.status_text}</p>
			{/if}
		</section>

		<section class="command">
			<h3>{t('form.sendCommand')}</h3>
			<p class="note">{t('form.sendCommandNote', { endpoint: '/api/boss/sessions/:id/message' })}</p>
			<button type="button" class="send" disabled title={t('form.endpointUnavailable')}>
				{t('form.sendCommand')}…
			</button>
		</section>

		<section class="msgs">
			<h3>{t('form.recentMessages')}</h3>
			{#if error}
				<ErrorState message={error} onRetry={onRetry} />
			{:else if loading}
				<Skeleton rows={4} />
			{:else if messages.length === 0}
				<EmptyState title={t('page.noRecentMessages')} detail={t('form.sessionNoTraffic')} />
			{:else}
				<ul class="list">
					{#each messages as message (message.id)}
						<li>
							<div class="m-top">
								<AgentIdentity name={message.agent_name} />
								<span class="when">{formatRelativeTime(message.created_at)}</span>
							</div>
							<p class="m-body">{truncateBody(message.body, 140)}</p>
							<StatusBadges
								priority={message.priority}
								direction={message.direction}
								compact
							/>
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	</div>
</div>

<style>
	.drawer {
		display: flex;
		flex-direction: column;
		width: min(380px, 100%);
		height: 100%;
		background: var(--hb-bg-panel);
		border-left: 1px solid var(--hb-border);
		box-shadow: var(--hb-shadow);
	}
	.head {
		display: flex;
		align-items: flex-start;
		gap: 0.5rem;
		padding: 0.85rem 1rem;
		border-bottom: 1px solid var(--hb-border-subtle);
	}
	.titles {
		min-width: 0;
		flex: 1;
	}
	.pill {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}
	h2 {
		margin: 0.15rem 0 0;
		font-size: 1rem;
		font-weight: 700;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.close {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		width: 1.75rem;
		height: 1.75rem;
		cursor: pointer;
		flex-shrink: 0;
	}
	.body {
		flex: 1;
		overflow-y: auto;
		padding: 0.85rem 1rem 1.25rem;
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	.meta .row {
		display: grid;
		grid-template-columns: 5rem 1fr;
		gap: 0.5rem;
		align-items: center;
		margin-bottom: 0.4rem;
		font-size: 12px;
	}
	.k {
		color: var(--hb-text-dim);
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.mono {
		font-family: var(--hb-font-mono);
		font-size: 11px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.mono.path {
		white-space: normal;
		word-break: break-all;
	}
	.status-text {
		margin: 0.5rem 0 0;
		padding: 0.5rem 0.6rem;
		background: var(--hb-bg-input);
		border-radius: var(--hb-radius-sm);
		border: 1px solid var(--hb-border-subtle);
		color: var(--hb-text-muted);
		font-size: 12px;
		line-height: 1.4;
	}
	h3 {
		margin: 0 0 0.45rem;
		font-size: 11px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.command .note {
		margin: 0 0 0.55rem;
		font-size: 11px;
		color: var(--hb-text-dim);
		line-height: 1.4;
	}
	.send {
		width: 100%;
		border: 1px dashed var(--hb-border);
		background: var(--hb-bg-input);
		border-radius: var(--hb-radius-sm);
		padding: 0.45rem 0.7rem;
		color: var(--hb-text-dim);
		cursor: not-allowed;
		opacity: 0.7;
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
	}
	.list li {
		padding: 0.55rem 0.6rem;
		border: 1px solid var(--hb-border-subtle);
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-elevated);
	}
	.m-top {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		margin-bottom: 0.25rem;
	}
	.when {
		margin-left: auto;
		font-size: 10px;
		color: var(--hb-text-dim);
	}
	.m-body {
		margin: 0 0 0.35rem;
		font-size: 12px;
		color: var(--hb-text);
		line-height: 1.35;
	}
</style>
