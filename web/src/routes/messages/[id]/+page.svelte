<!-- Addressable message and decision detail.
     Reads the boss-scoped message, including its recorded replies. -->
<script lang="ts">
	import { tick, untrack } from 'svelte';
	import { page } from '$app/state';
	import { auth } from '$lib/stores/auth.svelte';
	import { directionLabel, priorityLabel, statusLabel } from '$lib/design/semantics';
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
	let earlier = $state<MessageResponse[]>([]);
	let heading = $state<HTMLHeadingElement>();
	let generation = 0;
	const from = $derived(page.url.searchParams.get('from'));
	const back = $derived(from === 'today' ? '/' : from === 'session' && message?.session_id
		? '/sessions/' + encodeURIComponent(message.session_id) : '/messages');
	const integration = $derived(message?.metadata?.integration === true || message?.metadata?.source === 'webhook'
		|| message?.metadata?.rich_content !== undefined);

	async function load(id: string) {
		const request = ++generation;
		try {
			const client = auth.client;
			const current = await client?.message(id);
			if (request !== generation || !current) return;
			const first = !message;
			message = current;
			if (first && matchMedia('(max-width: 767px)').matches) {
				await tick();
				heading?.focus();
			}
			if (current.session_id && isDecision(current)) {
				const history = await client?.messages({ session: current.session_id, direction: 'all', limit: 50 });
				if (request === generation && history) earlier = history.messages
					.filter((item) => Date.parse(item.created_at) < Date.parse(current.created_at)).slice(0, 5);
			}
		} catch (failure) {
			if (request === generation && !message) error = apiErrorMessage(failure);
		}
	}

	$effect(() => {
		message = null;
		error = null;
		earlier = [];
		const id = page.params.id ?? '';
		untrack(() => { void load(id); });
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
		<h1 bind:this={heading} tabindex="-1" title={message.body}><InlineText text={Array.from(message.body).slice(0, 144).join('')} markdown={false} /></h1>
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
			<a class="back" href={'/sessions/' + encodeURIComponent(message.session_id)}>{t('console.openSession')}</a>
		{/if}
		{#if earlier.length}
			<aside>
				<h2>{t('console.earlier')}</h2>
				<ul>
					{#each earlier as item (item.id)}
						<li><a href={'/messages/' + encodeURIComponent(item.id)}>{item.body}</a></li>
					{/each}
				</ul>
			</aside>
		{/if}
		<details>
			<summary>{t('console.details')}</summary>
			<dl>
				<dt>{t('form.status')}</dt><dd>{statusLabel(message.status)}</dd>
				<dt>{t('form.priority')}</dt><dd>{priorityLabel(message.priority)}</dd>
				<dt>{t('form.direction')}</dt><dd>{directionLabel(message.direction)}</dd>
				<dt>{t('form.created')}</dt><dd>{formatDateTime(message.created_at)}</dd>
				<dt>{t('form.updated')}</dt><dd>{formatDateTime(message.updated_at)}</dd>
				<dt>{t('form.channel')}</dt><dd>{message.channel ?? '—'}</dd>
				{#if message.expires_at}<dt>{t('form.expires')}</dt><dd>{formatDateTime(message.expires_at)}</dd>{/if}
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
