<!-- Client inventory with current-browser attribution and confirmed revocation.
     Depends on the authenticated boss API, shared states, and four-locale copy. -->
<script lang="ts">
	import { onMount } from 'svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { formatDateTime, t } from '$lib/i18n';
	import type { BossClient } from '$lib/api/clients';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import { ApiError } from '$lib/api/types';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import CopyBlock from '$lib/message/CopyBlock.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';

	let clients = $state<BossClient[]>([]);
	let loading = $state(true);
	let pending = $state<string | null>(null);
	let error = $state<string | null>(null);
	let confirm = $state<BossClient | null>(null);
	let pairing = $state<{ code: string; expires_at: string } | null>(null);
	let pairingAvailable = $state(true);
	let pairingBusy = $state(false);
	let pairingError = $state('');

	async function addDevice() {
		const client = auth.client;
		if (!client || pairingBusy) return;
		pairingBusy = true;
		pairingError = '';
		try { pairing = await client.createPairing(); }
		catch (failure) {
			if (failure instanceof ApiError && [404, 405].includes(failure.status)) pairingAvailable = false;
			else pairingError = failure instanceof Error ? failure.message : String(failure);
		} finally { pairingBusy = false; }
	}

	async function load(): Promise<void> {
		if (pending) return;
		loading = true;
		error = null;
		try {
			if (!auth.client) throw new Error(t('top.offline'));
			clients = await auth.client.clients();
		} catch (cause) {
			error = cause instanceof Error ? cause.message : String(cause);
		} finally {
			loading = false;
		}
	}

	async function revoke(client: BossClient): Promise<void> {
		if (pending || client.is_current || client.revoked_at || !auth.client) return;
		pending = client.id;
		error = null;
		try {
			await auth.client.revokeClient(client.id);
			clients = await auth.client.clients();
		} catch (cause) {
			error = cause instanceof Error ? cause.message : String(cause);
		} finally {
			pending = null;
		}
	}

	function date(value: string | null): string {
		if (!value) return t('common.never');
		return formatDateTime(value.includes('T') ? value : `${value.replace(' ', 'T')}Z`);
	}
	onMount(() => { void load(); });
</script>

<section class="page">
	<header>
		<h1>{t('page.devices')}</h1>
		{#if pairingAvailable && auth.connection?.boss?.role !== 'viewer'}
			<button onclick={addDevice} disabled={pairingBusy}>{t('console.addDevice')}</button>
		{/if}
		<button onclick={load} disabled={loading || pending !== null}>{t('common.refresh')}</button>
	</header>
	{#if pairing}
		<CopyBlock text={pairing.code} label={t('console.pairExpires', { time: formatDateTime(pairing.expires_at) })} />
	{/if}
	{#if pairingError}<p role="alert">{pairingError}</p>{/if}
	{#if confirm}
		{@const current = confirm}
		<ConfirmDialog action={t('devices.revoke')} message={t('devices.confirm', { name: current.label })}
			onConfirm={() => revoke(current)} onClose={() => { confirm = null; }} />
	{/if}
	{#if error}<ErrorState message={error} onRetry={load} />{/if}
	{#if loading && clients.length === 0}
		<Skeleton rows={4} />
	{:else if !error && clients.length === 0}
		<EmptyState title={t('devices.empty')} detail={t('page.devicesSub')} />
	{:else}
		<ul>
			{#each clients as client (client.id)}
				<li class:revoked={!!client.revoked_at}>
					<div class="identity"><strong>{client.label}</strong>
						{#if client.is_current}<span class="badge live">{t('devices.thisBrowser')}</span>{/if}
						{#if client.revoked_at}<span>{t('devices.revoked')} · {date(client.revoked_at)}</span>{/if}
					</div>
					<dl>
						<div><dt>{t('devices.kind')}</dt><dd>{client.kind}</dd></div>
						<div><dt>{t('form.created')}</dt><dd>{date(client.created_at)}</dd></div>
						<div><dt>{t('form.lastSeen')}</dt><dd>{date(client.last_seen_at)}</dd></div>
						<div><dt>{t('devices.push')}</dt><dd>{t(client.has_push_device ? 'devices.attached' : 'devices.none')}</dd></div>
						<div><dt>{t('devices.signing')}</dt><dd>{t(client.has_signing_key ? 'devices.attached' : 'devices.none')}</dd></div>
					</dl>
					{#if !client.is_current && !client.revoked_at}
						<button class="revoke" onclick={() => { confirm = client; }} disabled={pending !== null || loading}>
							{t(pending === client.id ? 'devices.revoking' : 'devices.revoke')}
						</button>
					{/if}
				</li>
			{/each}
		</ul>
	{/if}
</section>

<style>
	.page { max-width: 80rem; margin: 0 auto; }
	header { display: flex; align-items: center; flex-wrap: wrap; gap: 12px; margin-bottom: 1.5rem; }
	h1 { font: var(--t-large); margin: 0 auto 0 0; }
	p, dt { color: var(--hb-text-muted); }
	p { font-size: 0.8rem; margin: 0.4rem 0 0; }
	ul { list-style: none; padding: 0; margin: 0; background: var(--surface);
		border: 1px solid var(--border); border-radius: var(--r-l); container-type: inline-size; }
	li { padding: 12px 16px; }
	li + li { border-block-start: 1px solid var(--hairline); }
	.revoked { color: var(--text-3); }
	.identity { display: flex; align-items: center; gap: 0.8rem; flex-wrap: wrap; overflow-wrap: anywhere; }
	.identity span { font-size: 0.75rem; color: var(--hb-text-muted); }
	.identity .badge { color: var(--live); }
	dl { display: flex; flex-wrap: wrap; gap: 1rem 2rem; font-size: 0.8rem; }
	dt { margin-bottom: 0.35rem; }
	dd { margin: 0; }
	button { min-height: var(--hit); border: 1px solid var(--hb-border); background: var(--hb-bg-elevated); color: var(--hb-text); padding: 0.5rem 0.8rem; border-radius: var(--hb-radius-sm); cursor: pointer; }
	button:disabled { opacity: 0.5; cursor: not-allowed; }
	.revoke { color: var(--danger); }
	@container (width < 600px) {
		dl, dl div { display: grid; gap: 4px 12px; }
		dl div { grid-template-columns: minmax(96px, 35%) minmax(0, 1fr); }
	}
</style>
