<!-- Shared answer controls and outcome wording for the three decision surfaces.
     A decision must be open in the current server snapshot to accept input. -->
<script lang="ts">
	import { untrack } from 'svelte';
	import DecisionDeadline from './DecisionDeadline.svelte';
	import { crossedThreshold, remainingTime } from './timing';
	import { extractOptions, extractOptionMedia } from '$lib/api/mappers';
	import { ApiError, apiErrorMessage, type MessageResponse } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { formatDateTime, getLocale, t } from '$lib/i18n';
	import MessageAttachment from '$lib/message/MessageAttachment.svelte';
	import { safeLink } from '$lib/message/inline';
	import { answerability } from './answerability';
	import { deadlineOf } from './decision';
	import { inputs } from './inputs.svelte';

	let { message, custom = false, showDeadline = true, onUpdate }: {
		message: MessageResponse; custom?: boolean; showDeadline?: boolean; onUpdate?: (message: MessageResponse) => void;
	} = $props();
	let response = $state<MessageResponse | null>(null);
	let draft = $state('');
	let busy = $state(false);
	let error = $state<string | null>(null);
	const options = $derived(extractOptions(message.metadata));
	const media = $derived(extractOptionMedia(message.metadata));
	const gallery = $derived(media.flatMap(({ url, label, caption }) => {
		const href = safeLink(url);
		return href && options.includes(label) ? [{ href, label: caption || label }] : [];
	}));
	const deadline = $derived(deadlineOf(message));
	const result = $derived(response ?? message.replies?.find((reply) => reply.direction === 'boss_to_agent'));
	const status = $derived(answerability(message.id, new Set(inputs.messages.map(({ id }) => id)),
		inputs.loaded, inputs.settled, deadline, inputs.now));
	const seconds = $derived(deadline ? Math.max(0, Math.ceil((Date.parse(deadline) - inputs.now) / 1000)) : 0);
	const remaining = $derived(remainingTime(seconds, getLocale()));
	let announcement = $state('');
	let previous = 0;
	const announced = new Set<number>();
	$effect(() => {
		const threshold = crossedThreshold(previous, seconds);
		previous = seconds;
		if (status === 'open' && threshold && !announced.has(threshold)) {
			announced.add(threshold);
			announcement = untrack(() => t('console.timeLeft', { time: remainingTime(threshold, getLocale()) }));
		}
	});
	const viewer = $derived(auth.connection?.boss?.role === 'viewer');
	let fetched = false;

	$effect(() => {
		if (status === 'closed' && !result && !fetched) {
			fetched = true;
			void readOutcome();
		}
	});

	async function readOutcome() {
		try {
			const updated = await auth.client?.message(message.id);
			if (!updated) return;
			onUpdate?.(updated);
			response = updated.replies?.find((reply) => reply.direction === 'boss_to_agent') ?? response;
		} catch { /* Retain local closure until the server confirms the outcome. */ }
	}

	async function answer(body: string) {
		const client = auth.client;
		if (!client || busy || status !== 'open' || viewer || !body.trim()) return;
		busy = true;
		error = null;
		try {
			response = await client.reply(message.id, { body: body.trim() });
			inputs.close(message.id);
		} catch (failure) {
			if (!(failure instanceof ApiError) || failure.status !== 409) {
				error = apiErrorMessage(failure);
				return;
			}
			inputs.close(message.id);
		} finally {
			busy = false;
		}
		await readOutcome();
	}
</script>

<span class="announcement" aria-live="polite" aria-atomic="true">{announcement}</span>
{#if result}
	<p role="status" class="banner" class:settled={!result.metadata?.auto_default}>
		{result.metadata?.auto_default ? t('console.defaultPicked')
			: t('console.answered', { option: result.body, time: formatDateTime(result.created_at) })}
	</p>
{:else if status === 'closed'}
	<p role="status" class="banner">{t('console.closed')}</p>
{:else}
	{#if showDeadline}<p class="banner signal"><DecisionDeadline {deadline} /></p>{/if}
	{#if status === 'checking'}<p role="status">{t('console.checking')}</p>{/if}
	{#if viewer}<p>{t('console.viewOnly')}</p>{/if}
	<div class="options" class:paired={options.length === 2 && media.length === 0}>
		{#each options as option, index}
			{@const illustration = media.find(({ label }) => label === option)}
			{@const image = safeLink(illustration?.url)}
			<div class="option">
				{#if image}
					<MessageAttachment href={image} imageLabel={illustration?.caption || option} {gallery} />
				{/if}
				{#if viewer}
					<span>{option}</span>
				{:else}
					<button type="button" class:primary={index === 0} disabled={busy || status !== 'open'}
					onclick={() => answer(option)}>
					<strong>{option}</strong>
					{#if illustration?.caption}<span>{illustration.caption}</span>{/if}
					</button>
				{/if}
			</div>
		{/each}
	</div>
	{#if deadline && status === 'open' && typeof message.metadata?.default_option === 'string'}
		<p class="default-line">{t('console.default', { time: remaining, option: message.metadata.default_option })}</p>
	{/if}
	{#if custom && !viewer}
		<form onsubmit={(event) => { event.preventDefault(); void answer(draft); }}>
			<label for={'answer-' + message.id}>{t('form.writeReply')}</label>
			<textarea id={'answer-' + message.id} bind:value={draft} disabled={busy || status !== 'open'}></textarea>
			<button disabled={busy || status !== 'open' || !draft.trim()}>{t('form.sendReply')}</button>
		</form>
	{/if}
	{#if error}<p role="alert">{error}</p>{/if}
{/if}

<style>
	.announcement { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
	.default-line { font: var(--t-footnote); color: var(--text-2); margin-block-end: 0; }
	.banner { padding: 12px; border-radius: var(--r-m); background: var(--neutral-soft); }
	.settled { background: var(--settled-soft); color: var(--settled); }
	.signal { background: var(--signal-soft); color: var(--signal); }
	.options, form { display: grid; gap: 8px; }
	.paired { grid-template-columns: repeat(2, minmax(0, 1fr)); }
	form { margin-block-start: 12px; }
	button { min-height: var(--hit); border: 1px solid var(--field-border); background: var(--surface);
		border-radius: var(--r-s); padding: 8px 12px; overflow-wrap: anywhere; text-align: start; }
	.primary { background: var(--ink); color: var(--on-ink); }
	button:disabled { opacity: 0.55; }
	.option { display: grid; gap: 4px; }
	button span { display: block; }
	textarea { min-height: 72px; border: 1px solid var(--field-border); border-radius: var(--r-s); }
</style>
