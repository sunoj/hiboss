<script lang="ts">
	import { ApiError, type MessageResponse } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { toasts } from '$lib/stores/toast.svelte';
	import { t } from '$lib/i18n';

	interface Props {
		messageId: string;
		options: string[];
		optionsExpired: boolean;
		onUpdated?: (message: MessageResponse) => void;
	}

	let { messageId, options, optionsExpired, onUpdated }: Props = $props();

	let replyText = $state('');
	let busy = $state(false);
	let forwardChannel = $state<'discord' | 'telegram'>('discord');

	const REACTIONS = ['👀', '🔨', '✅'] as const;

	async function withBusy(action: () => Promise<void>): Promise<void> {
		if (busy) return;
		if (!auth.client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		busy = true;
		try {
			await action();
		} catch (e) {
			const msg = e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
			toasts.push(msg, 'error');
		} finally {
			busy = false;
		}
	}

	async function sendReply(body: string) {
		const text = body.trim();
		if (!text) {
			toasts.push(t('form.replyEmpty'), 'warning');
			return;
		}
		await withBusy(async () => {
			const updated = await auth.client!.reply(messageId, { body: text });
			toasts.push(t('form.sendReply'), 'success');
			replyText = '';
			onUpdated?.(updated);
		});
	}

	async function sendReact(emoji: string) {
		await withBusy(async () => {
			await auth.client!.react(messageId, { emoji });
			toasts.push(t('form.reacted', { emoji }), 'success');
		});
	}

	async function sendForward() {
		await withBusy(async () => {
			const updated = await auth.client!.forward(messageId, { channel: forwardChannel });
			toasts.push(t('form.forwarded', { channel: forwardChannel }), 'success');
			onUpdated?.(updated);
		});
	}
</script>

{#if options.length > 0}
	<section class="block" aria-label={t('form.messageOptions')}>
		<h3>{t('form.options')}</h3>
		{#if optionsExpired}
			<p class="hint">{t('form.optionsExpired')}</p>
		{/if}
		<div class="row">
			{#each options as option (option)}
				<button
					type="button"
					class="btn"
					disabled={busy || optionsExpired}
					onclick={() => sendReply(option)}
				>
					{option}
				</button>
			{/each}
		</div>
	</section>
{/if}

<section class="block">
	<h3>{t('form.sendReply')}</h3>
	<textarea rows="3" placeholder={t('form.writeReply')} bind:value={replyText} disabled={busy}></textarea>
	<button type="button" class="btn primary" disabled={busy} onclick={() => sendReply(replyText)}>
		{t('form.sendReply')}
	</button>
</section>

<section class="block">
	<h3>{t('form.react')}</h3>
	<div class="row">
		{#each REACTIONS as emoji (emoji)}
			<button type="button" class="btn" disabled={busy} onclick={() => sendReact(emoji)}>
				{emoji}
			</button>
		{/each}
	</div>
</section>

<section class="block">
	<h3>{t('form.forward')}</h3>
	<div class="forward">
		<select bind:value={forwardChannel} disabled={busy}>
			<option value="discord">Discord</option>
			<option value="telegram">Telegram</option>
		</select>
		<button type="button" class="btn primary" disabled={busy} onclick={sendForward}>{t('form.forward')}</button>
	</div>
</section>

<style>
	.block {
		padding-top: 0.35rem;
		border-top: 1px solid var(--hb-border-subtle);
	}
	h3 {
		margin: 0 0 0.4rem;
		font-size: 11px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.hint {
		margin: 0 0 0.4rem;
		font-size: 11px;
		color: var(--hb-danger);
	}
	.row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}
	.btn {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.65rem;
		cursor: pointer;
		color: var(--hb-text);
		font: inherit;
		font-size: 12px;
	}
	.btn:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.btn:disabled,
	textarea:disabled,
	select:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}
	.primary {
		border-color: var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 22%, var(--hb-bg-elevated));
		font-weight: 600;
	}
	textarea,
	select {
		width: 100%;
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-input);
		color: var(--hb-text);
		border-radius: var(--hb-radius-sm);
		padding: 0.45rem 0.55rem;
		font: inherit;
		font-size: 12px;
		resize: vertical;
		margin-bottom: 0.45rem;
		box-sizing: border-box;
	}
	.forward {
		display: flex;
		gap: 0.45rem;
		align-items: center;
	}
	.forward select {
		margin: 0;
		flex: 1;
	}
</style>
