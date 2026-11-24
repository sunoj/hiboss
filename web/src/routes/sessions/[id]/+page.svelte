<!-- Addressable session transcript and its reply/note composer.
     Falls back to the loaded conversation if optional endpoints are unavailable. -->
<script lang="ts">
	import { sessionPanels, type PanelSummary } from '$lib/api/session-panels';
	import { readEventStream } from '$lib/api/event-stream';
	import { page } from '$app/state';
	import { auth } from '$lib/stores/auth.svelte';
	import { ApiError, apiErrorMessage, type MessageResponse, type SessionResponse } from '$lib/api/types';
	import { formatDateTime, t } from '$lib/i18n';
	import { isDecision } from '$lib/decisions/decision';
	import DecisionActions from '$lib/decisions/DecisionActions.svelte';
	import MessageContent from '$lib/message/MessageContent.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';

	let session = $state<SessionResponse | null>(null);
	let messages = $state<MessageResponse[]>([]);
	let panels = $state<PanelSummary[]>([]);
	let notes = $state<{ id: string; body: string }[]>([]);
	let notesAvailable = $state(false);
	let loadedAt = $state('');
	let error = $state<string | null>(null);
	let composeError = $state<string | null>(null);
	let draft = $state('');
	let note = $state(false);
	let busy = $state(false);
	let generation = 0;
	const id = $derived(page.params.id ?? '');
	const integration = $derived(messages.some(({ metadata }) => metadata?.integration === true || metadata?.source === 'webhook'));
	const target = $derived(!integration && session?.status !== 'completed'
		? messages.findLast((message) => message.direction === 'agent_to_boss' && !isDecision(message)) : undefined);
	const replies = $derived(new Set(messages.filter(isDecision).flatMap((message) => message.replies?.map(({ id }) => id) ?? [])));
	const canWrite = $derived(auth.connection?.boss?.role !== 'viewer' && !integration);

	async function load(sessionId: string) {
		const client = auth.client;
		if (!client) return;
		const request = ++generation;
		error = null;
		const [list, transcript, availableNotes] = await Promise.allSettled([
			client.sessions(), client.messages({ session: sessionId, direction: 'all', limit: 100 }), client.sessionNotes(sessionId)
		]);
		if (request !== generation) return;
		if (list.status === 'fulfilled') session = list.value.sessions.find(({ id }) => id === sessionId) ?? null;
		if (transcript.status === 'fulfilled') {
			const chronological = [...transcript.value.messages].reverse();
			messages = chronological.map((message) => isDecision(message)
				? { ...message, replies: chronological.filter((reply) => reply.reply_to === message.id) } : message);
			loadedAt = new Date().toISOString();
		} else error = apiErrorMessage(transcript.reason);
		if (list.status === 'rejected') error = apiErrorMessage(list.reason);
		notesAvailable = availableNotes.status === 'fulfilled';
		if (availableNotes.status === 'fulfilled') notes = availableNotes.value.notes;
	}

	async function send(event: SubmitEvent) {
		event.preventDefault();
		const client = auth.client;
		if (!client || !canWrite || busy || !draft.trim()) return;
		const sessionId = id;
		composeError = null;
		busy = true;
		try {
			if (note && notesAvailable) await client.createSessionNote(sessionId, draft.trim());
			else if (target) await client.reply(target.id, { body: draft.trim() });
			else return;
			if (id === sessionId) {
				draft = '';
				await load(sessionId);
			}
		} catch (failure) {
			if (failure instanceof ApiError && [404, 405].includes(failure.status) && note) notesAvailable = false;
			composeError = apiErrorMessage(failure);
		} finally {
			busy = false;
		}
	}

	async function watch(sessionId: string, signal: AbortSignal) {
		const client = auth.client;
		if (!client) return;
		try {
			const events = await client.sessionEvents(sessionId);
			if (signal.aborted) return;
			const path = client.baseUrl + '/api/sessions/' + encodeURIComponent(sessionId) + '/stream'
				+ (events.next_after === null ? '' : '?after=' + events.next_after);
			let refresh: ReturnType<typeof setTimeout>;
			signal.addEventListener('abort', () => clearTimeout(refresh), { once: true });
			await readEventStream(path, client.streamHeaders(), signal, (event) => {
				if (event !== 'session_event') return;
				clearTimeout(refresh);
				refresh = setTimeout(() => { if (!signal.aborted) void load(sessionId); }, 200);
			});
		} catch { /* The loaded transcript remains available on older or offline servers. */ }
	}

	$effect(() => {
		session = null; messages = []; notes = []; panels = []; notesAvailable = false; loadedAt = '';
		draft = ''; note = false; composeError = null;
		const stop = new AbortController();
		void load(id);
		void watch(id, stop.signal);
		const client = auth.client;
		if (client) {
			void sessionPanels(client, id, stop.signal).then((rows) => {
				if (!stop.signal.aborted) panels = rows;
			}).catch(() => undefined);
		}
		return () => stop.abort();
	});
</script>

<section class="detail">
	<a href="/sessions">← {t('nav.sessions')}</a>
	{#if session}
		<h1>{[session.project_slug ?? session.label ?? session.id, session.branch].filter(Boolean).join(' · ')}</h1>
		<p>{[session.agent_name, session.status_text].filter(Boolean).join(' · ')}</p>
		{#if integration}<p>{t('console.integration')}</p>{/if}
		<details>
			<summary>{t('console.details')}</summary>
			<p><code>{session.id}</code></p>
			{#if session.cwd}<p><code>{session.cwd}</code></p>{/if}
			<time datetime={session.last_seen_at}>{formatDateTime(session.last_seen_at)}</time>
		</details>
	{/if}
	{#if error}<ErrorState message={error} onRetry={() => load(id)} />{/if}
	{#if loadedAt && !error}
		<time datetime={loadedAt} title={formatDateTime(loadedAt)}>
			{t('form.updated')} {formatDateTime(loadedAt)}
		</time>
		<div role="feed" aria-label={t('console.transcript')}>
			{#each messages.filter(({ id }) => !replies.has(id)) as message (message.id)}
				<article aria-label={message.body}>
					<a href={'/messages/' + encodeURIComponent(message.id) + '?from=session'}>{message.body}</a>
					<MessageContent metadata={message.metadata} />
					{#if isDecision(message)}<DecisionActions {message} />{/if}
				</article>
			{/each}
			{#each panels as panel (panel.panelId)}
				{@const updated = panel.lifecycle.lastObservedAt ?? panel.createdAt}
				<article aria-label={panel.title}>
					<strong>{panel.title}</strong>
					<p>{t(panel.questionnaire ? 'console.inApps' : 'console.panel')} · {panel.lifecycle.taskState}</p>
					<time datetime={updated} title={formatDateTime(updated)}>{formatDateTime(updated)}</time>
				</article>
			{/each}
			{#each notes as item (item.id)}
				<article aria-label={t('console.sessionNote')}><p>{item.body}</p></article>
			{/each}
		</div>
		{#if canWrite}
			<form onsubmit={send}>
				{#if notesAvailable}
					<label><input type="checkbox" bind:checked={note} /> {t('console.sessionNote')}</label>
				{/if}
				{#if target || (note && notesAvailable)}
					<label for="session-compose">{t(note ? 'console.sessionNote' : 'form.writeReply')}</label>
					<textarea id="session-compose" bind:value={draft} disabled={busy}></textarea>
					<button disabled={busy || !draft.trim()}>{t(note ? 'console.sessionNote' : 'form.sendReply')}</button>
				{:else}
					<p>{t('console.noReplyTarget')}</p>
				{/if}
				{#if composeError}<p role="alert">{composeError}</p>{/if}
			</form>
		{:else if integration}
			<p>{t('console.integrationReply')}</p>
		{/if}
	{:else if !error}
		<p role="status">{t('app.loading')}</p>
	{/if}
</section>

<style>
	.detail { background: var(--surface); border: 1px solid var(--border); padding: 16px;
		border-radius: var(--r-m); overflow-wrap: anywhere; }
	h1 { font: var(--t-title); }
	a { color: var(--live); text-decoration: underline; }
	time { color: var(--text-3); font: var(--t-caption); }
	article { border-block-start: 1px solid var(--hairline); padding: 12px 0; }
	form { display: grid; gap: 8px; }
	button, textarea { min-height: var(--hit); }
</style>
