<!-- Addressable message and decision detail.
     Reads the boss-scoped message, including its recorded replies. -->
<script lang="ts">
	import { page } from '$app/state';
	import { auth } from '$lib/stores/auth.svelte';
	import { formatDateTime, t } from '$lib/i18n';
	import { apiErrorMessage, type MessageResponse } from '$lib/api/types';
	import InlineText from '$lib/message/InlineText.svelte';
	import MessageContent from '$lib/message/MessageContent.svelte';
	import { isDecision } from '$lib/decisions/decision';
	import DecisionActions from '$lib/decisions/DecisionActions.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import MessageDrawerActions from '../MessageDrawerActions.svelte';

	let message = $state<MessageResponse | null>(null);
	let error = $state<string | null>(null);
	let generation = 0;
	const from = $derived(page.url.searchParams.get('from'));
	const back = $derived(from === 'today' ? '/' : from === 'session' && message?.session_id
		? '/sessions/' + encodeURIComponent(message.session_id) : '/messages');
	const integration = $derived(message?.metadata?.integration === true
		|| message?.metadata?.rich_content !== undefined);

	async function load(id: string) {
		const request = ++generation;
		try {
			const current = await auth.client?.message(id);
			if (request === generation && current) message = current;
		} catch (failure) {
			if (request === generation) error = apiErrorMessage(failure);
		}
	}

	$effect(() => {
		message = null;
		error = null;
		void load(page.params.id ?? '');
	});
</script>

<section class="message-detail">
	<a class="back" href={back}>← {t(from === 'today' ? 'nav.dashboard'
		: from === 'session' ? 'nav.sessions' : 'nav.messages')}</a>
	{#if error}
		<ErrorState message={error} onRetry={() => { error = null; void load(page.params.id ?? ''); }} />
	{:else if message}
		<p class="provenance">{[message.session_label, message.session_branch, message.agent_name]
			.filter(Boolean).join(' · ')}</p>
		<h1 title={message.body}><InlineText text={Array.from(message.body).slice(0, 144).join('')} markdown={false} /></h1>
		<time datetime={message.created_at} title={formatDateTime(message.created_at)}>
			{formatDateTime(message.created_at)}
		</time>
		{#if integration}<p>{t('console.integration')}</p>{/if}
		{#if message.direction === 'agent_to_agent'}<p>{t('console.peer')}</p>{/if}
		<MessageContent metadata={message.metadata} expanded={page.url.searchParams.has('search')} />
		{#if isDecision(message)}
			{#key message.id}<DecisionActions {message} custom onUpdate={(updated) => { message = updated; }} />{/key}
		{:else if auth.connection?.boss?.role !== 'viewer' && message.direction === 'agent_to_boss'}
			{#if integration}<p>{t('console.integrationReply')}</p>{/if}
			{#key message.id}
				<MessageDrawerActions messageId={message.id} options={[]} optionMedia={[]} optionsExpired={false}
					replyDisabled={integration} onUpdated={() => load(page.params.id ?? '')} />
			{/key}
		{/if}
		{#if message.session_id}
			<a class="back" href={'/sessions/' + encodeURIComponent(message.session_id)}>{t('nav.sessions')}</a>
		{/if}
		<details>
			<summary>{t('console.details')}</summary>
			<dl>
				<dt>{t('form.created')}</dt><dd>{formatDateTime(message.created_at)}</dd>
				<dt>{t('form.updated')}</dt><dd>{formatDateTime(message.updated_at)}</dd>
				<dt>{t('form.channel')}</dt><dd>{message.channel ?? '—'}</dd>
			</dl>
			<code>{message.id}</code>
		</details>
	{:else}
		<p role="status">{t('app.loading')}</p>
	{/if}
</section>

<style>
	.message-detail { background: var(--surface); border: 1px solid var(--border); padding: 16px;
		border-radius: var(--r-m); display: grid; gap: 12px; overflow-wrap: anywhere; }
	p, h1, dl { margin: 0; }
	h1 { font: var(--t-large); }
	time, .provenance { font: var(--t-caption); color: var(--text-3); }
	.back { color: var(--live); text-decoration: underline; }
	summary { min-height: var(--hit); cursor: pointer; }
</style>
