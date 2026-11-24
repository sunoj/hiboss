<!-- Daily decisions, active work, and delivered messages.
     Open decisions come from the authenticated required-input stream. -->
<script lang="ts">
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import { inputs } from '$lib/decisions/inputs.svelte';
	import { compareDecisions, deadlineOf, isDecision } from '$lib/decisions/decision';
	import DecisionActions from '$lib/decisions/DecisionActions.svelte';
	import MessageRow from './MessageRow.svelte';
	import Skeleton from './Skeleton.svelte';
	import ErrorState from './ErrorState.svelte';
	import { untrack } from 'svelte';
	import { getLocale, t } from '$lib/i18n';
	import type { MessageResponse, SessionResponse } from '$lib/api/types';

	const loadState = new LoadState();
	let working = $state<SessionResponse[]>([]);
	let delivered = $state<MessageResponse[]>([]);
	let cards = $state<MessageResponse[]>([]);
	const open = $derived(inputs.messages.filter((message) => !inputs.settled.has(message.id)
		&& !(Date.parse(deadlineOf(message) ?? '') <= inputs.now)).sort(compareDecisions));
	$effect(() => {
		const latest = open;
		untrack(() => {
			const unique = new Map(cards.map((message) => [message.id, message]));
			for (const message of latest) unique.set(message.id, message);
			cards = [...unique.values()].sort(compareDecisions);
		});
	});
	const date = $derived(new Intl.DateTimeFormat(getLocale(), { dateStyle: 'full' }).format(inputs.now));

	async function load() {
		await loadState.run(async (client) => {
			const [sessions, messages] = await Promise.all([
				client.sessions(), client.messages({ direction: 'agent_to_boss', limit: 50 })
			]);
			working = sessions.sessions.filter((session) => session.status === 'working');
			delivered = messages.messages.filter((message) => !isDecision(message)).slice(0, 10);
		});
	}

	onMount(() => { void load(); });
</script>

<section class="today">
	<header><p>{date}</p><h1>{t('page.dashboard')}</h1></header>
	<div class="chips">
		<span class="signal">{inputs.loaded ? t('console.needYou', { count: open.length }) : t('app.loading')}</span>
		<span class="live">{t('page.working', { count: working.length })}</span>
		<span>{t(inputs.connected ? 'top.connected' : 'top.offline')}</span>
	</div>
	<h2>{t('console.yourCall')}</h2>
	{#if cards.length}
		{#each cards as message (message.id)}
			<article aria-label={message.body}>
				<p>{[message.session_label, message.session_branch, message.agent_name].filter(Boolean).join(' · ')}</p>
				<a class="question" href={'/messages/' + encodeURIComponent(message.id) + '?from=today'}>
					{Array.from(message.body).slice(0, 144).join('')}
				</a>
				<DecisionActions {message} onUpdate={(updated) => {
					cards = cards.map((item) => item.id === updated.id ? updated : item);
				}} />
			</article>
		{/each}
	{:else if !inputs.loaded}
		<article><Skeleton rows={2} /></article><article><Skeleton rows={2} /></article>
	{:else if inputs.connected}
		<article class="clear">{t('console.allClear')}</article>
	{/if}
	{#if loadState.error}<ErrorState message={loadState.error} onRetry={load} />{/if}
	{#if working.length}
		<h2>{t('console.workingNow')}</h2>
		<div class="rows">
			{#each working as session (session.id)}
				<a href={'/sessions/' + encodeURIComponent(session.id)}>
					{[session.label, session.branch, session.agent_name].filter(Boolean).join(' · ')}
				</a>
			{/each}
		</div>
		<a class="more" href="/sessions">{t('nav.sessions')}</a>
	{/if}
	{#if delivered.length}
		<h2>{t('console.delivered')}</h2>
		<div class="rows">
			{#each delivered as message (message.id)}
				<a href={'/messages/' + encodeURIComponent(message.id) + '?from=today'}><MessageRow {message} /></a>
			{/each}
		</div>
		<a class="more" href="/messages">{t('nav.messages')}</a>
	{/if}
</section>

<style>
	.today { max-width: var(--read); margin-inline: auto; }
	h1 { font: var(--t-large); margin: 0 0 16px; }
	h2 { font: var(--t-title); margin: 24px 0 12px; }
	p { font: var(--t-caption); color: var(--text-3); margin: 0 0 4px; }
	.chips { display: flex; flex-wrap: wrap; gap: 8px; }
	.chips span { border-radius: var(--r-pill); padding: 6px 12px; background: var(--surface); }
	.chips .signal { background: var(--signal-soft); color: var(--signal); }
	.chips .live { background: var(--live-soft); color: var(--live); }
	article, .rows { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-m); }
	article { padding: 16px; margin-block: 8px; }
	.clear { text-align: center; padding-block: 36px; }
	.question { font: var(--t-headline); overflow-wrap: anywhere; text-decoration: underline; }
	.rows > a { display: flex; align-items: center; min-height: var(--hit); padding: 0 12px; }
	.rows > a + a { border-block-start: 1px solid var(--hairline); }
	.more { color: var(--live); display: inline-block; margin-block-start: 8px; text-decoration: underline; }
</style>
