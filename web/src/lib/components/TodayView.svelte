<!-- Daily decisions, active work, and delivered messages.
     Open decisions come from the authenticated required-input stream. -->
<script lang="ts">
	import { onMount } from 'svelte';
	import { agentDirectory } from '$lib/stores/agents.svelte';
	import { isIntegrationMessage } from '$lib/api/agent-capabilities';
	import { auth } from '$lib/stores/auth.svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import { inputs } from '$lib/decisions/inputs.svelte';
	import { compareDecisions, deadlineOf, isDecision } from '$lib/decisions/decision';
	import DecisionActions from '$lib/decisions/DecisionActions.svelte';
	import IslandScene from './IslandScene.svelte';
	import FreshnessChip from './FreshnessChip.svelte';
	import ConsoleRow from './ConsoleRow.svelte';
	import DecisionDeadline from '$lib/decisions/DecisionDeadline.svelte';
	import { agentInitials } from '$lib/design/agent-color';
	import Skeleton from './Skeleton.svelte';
	import ErrorState from './ErrorState.svelte';
	import { untrack } from 'svelte';
	import { getLocale, t } from '$lib/i18n';
	import type { MessageResponse, SessionResponse } from '$lib/api/types';

	const loadState = new LoadState();
	let noAgents = $state(false);
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
				client.sessions(), client.messages({ direction: 'agent_to_boss', limit: 50 }), agentDirectory.load(client)
			]);
			noAgents = agentDirectory.rows.length === 0;
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
		<FreshnessChip updatedAt={inputs.updatedAt}
			status={inputs.connected ? 'online' : inputs.connecting ? 'connecting' : 'offline'} />
	</div>
	<h2>{t('console.yourCall')}</h2>
	{#if cards.length}
		{#each cards as message (message.id)}
			<article aria-label={message.body}>
				<p class="provenance">
					<span>{[message.session_label, message.session_branch, message.agent_name].filter(Boolean).join(' · ')}</span>
					{#if !inputs.settled.has(message.id) && !message.replies?.some((reply) => reply.direction === 'boss_to_agent')}
						<DecisionDeadline deadline={deadlineOf(message)} />
					{/if}
				</p>
				<a class="question" href={'/messages/' + encodeURIComponent(message.id) + '?from=today'}>
					{Array.from(message.body).slice(0, 144).join('')}
				</a>
				<DecisionActions {message} showDeadline={false} onUpdate={(updated) => {
					cards = cards.map((item) => item.id === updated.id ? updated : item);
				}} />
			</article>
		{/each}
	{:else if noAgents && auth.connection?.boss?.role === 'admin'}
		<article class="clear"><IslandScene /><a href="/agents?tab=join">{t('console.firstMachine')}</a></article>
	{:else if !inputs.loaded}
		<article><Skeleton rows={2} /></article><article><Skeleton rows={2} /></article>
	{:else if inputs.connected}
		<article class="clear"><IslandScene />{t('console.allClear')}</article>
	{/if}
	{#if loadState.error}<ErrorState message={loadState.error} onRetry={load} />{/if}
	{#if working.length}
		<h2>{t('console.workingNow')} <a class="more" href="/sessions">{t('console.allSessions')}</a></h2>
		<div class="rows">
			{#each working as session (session.id)}
				<ConsoleRow href={'/sessions/' + encodeURIComponent(session.id)}
					title={[session.project_slug ?? session.label, session.branch].filter(Boolean).join(' · ')}
					subtitle={[session.agent_name, session.status_text].filter(Boolean).join(' · ')}
					tile={agentInitials(session.project_slug ?? session.label ?? session.agent_name)}
					datetime={session.last_seen_at} live />
			{/each}
		</div>
	{/if}
	{#if delivered.length}
		<h2>{t('console.delivered')} <a class="more" href="/messages">{t('console.allMessages')}</a></h2>
		<div class="rows">
			{#each delivered as message (message.id)}
				{@const integration = isIntegrationMessage(message, agentDirectory.rows)}
				<ConsoleRow href={'/messages/' + encodeURIComponent(message.id) + '?from=today'} title={message.body}
					subtitle={[message.session_label, message.agent_name, integration && t('console.integration')]
						.filter(Boolean).join(' · ')}
					tile={agentInitials(message.session_label ?? message.agent_name)} datetime={message.created_at} />
			{/each}
		</div>
	{/if}
</section>

<style>
	.today { max-width: var(--read); margin-inline: auto; }
	h1 { font: var(--t-large); margin: 0 0 16px; }
	h2 { font: var(--t-footnote); color: var(--text-2); padding-inline: var(--s-4); margin: 24px 0 12px; display: flex; align-items: baseline; gap: 12px; }
	p { font: var(--t-caption); color: var(--text-3); margin: 0 0 4px; }
	.chips { display: flex; flex-wrap: wrap; gap: 8px; }
	.chips span { border-radius: var(--r-pill); padding: 6px 12px; background: var(--surface); }
	.chips .signal { background: var(--signal-soft); color: var(--signal); }
	.chips .live { background: var(--live-soft); color: var(--live); }
	article, .rows { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-m); }
	article { padding: 16px; margin-block: 8px; }
	.clear { text-align: center; padding-block: 36px; }
	.provenance { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 4px 12px; }
	.question { font: var(--t-headline); overflow-wrap: anywhere; }
	.question:hover, .more:hover { text-decoration: underline; }
	.rows { display: grid; overflow: hidden; }
	.rows > :global(a + a) { border-block-start: 1px solid var(--hairline); }
	.more { font: var(--t-footnote); color: var(--live); margin-inline-start: auto; }
</style>
