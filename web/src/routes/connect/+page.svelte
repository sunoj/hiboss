<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { onMount } from 'svelte';
	import { normalizeBaseUrl } from '$lib/api/auth';
	import { pairingCode } from '$lib/api/pairing';
	import ConsolePreferences from '$lib/components/ConsolePreferences.svelte';
	import CopyBlock from '$lib/message/CopyBlock.svelte';
	import { t } from '$lib/i18n';

	let baseUrl = $state(location.origin);
	let code = $state('');
	let reachable = $state<boolean | null>(null);
	let pairingMissing = $state(false);
	let host = $state(location.host);
	let probeVersion = 0;

	onMount(() => { void probe(); });

	async function probe(): Promise<void> {
		const version = ++probeVersion;
		reachable = null;
		pairingMissing = false;
		try {
			const url = new URL(baseUrl);
			host = url.host;
			const response = await fetch(url.origin, { signal: AbortSignal.timeout(5000) });
			if (version === probeVersion) reachable = response.ok;
		} catch {
			if (version === probeVersion) reachable = false;
		}
	}
	let token = $state('');
	let connecting = $state(false);
	let error = $state<string | null>(null);

	async function submit(event: Event, method: 'pair' | 'token'): Promise<void> {
		event.preventDefault();
		if (connecting) return;
		connecting = true;
		error = null;
		try {
			const origin = normalizeBaseUrl(baseUrl);
			if (method === 'pair') {
				const value = pairingCode(code);
				if (!/^hb_pair_[0-9a-f]{64}$/i.test(value)) throw new Error(t('console.invalidPair'));
				await auth.pair(origin, value);
			} else await auth.connect(origin, token.trim());
			await goto('/');
		} catch (err) {
			if (method === 'pair' && err && typeof err === 'object' && 'status' in err) {
				pairingMissing = err.status === 404 || err.status === 405;
				error = err.status === 400 ? t('console.invalidPair') : String(err);
			} else error = err instanceof Error ? err.message : String(err);
		} finally {
			connecting = false;
		}
	}

</script>

<main class="screen">
	<div class="card">
		<div class="brand">
			<span class="mark" aria-hidden="true">hb</span>
			<span class="name">HiBoss</span>
		</div>
		<ConsolePreferences />
		<h1>{t('console.connectBrowser')}</h1>
		{#if reachable !== null}
			<p role="status" class:reachable>{t(reachable ? 'console.reachable' : 'console.unreachable', { host })}</p>
		{/if}
		{#if reachable === false}
			<button type="button" onclick={probe}>{t('common.refresh')}</button>
		{:else if reachable}
			{#if !pairingMissing}
				<form onsubmit={(event) => submit(event, 'pair')}>
					<label>
						<span>{t('console.pairCode')}</span>
						<input bind:value={code} autocomplete="one-time-code" spellcheck="false"
							placeholder="hb_pair_…" aria-describedby="pair-help" required />
					</label>
					<p class="hint" id="pair-help">{t('console.pairHelp')}</p>
					<button class="primary" disabled={connecting || !code.trim()}>
						{t(connecting ? 'connect.connecting' : 'connect.connect')}
					</button>
				</form>
			{/if}
			<details open={pairingMissing}>
				<summary>{t('console.useToken')}</summary>
				<form onsubmit={(event) => submit(event, 'token')}>
					<label>
						<span>{t('connect.bossToken')}</span>
						<input type="password" bind:value={token} placeholder="hb_boss_…" required />
					</label>
					<button disabled={connecting || !token.trim()}>{t('connect.connect')}</button>
				</form>
			</details>
			<details>
				<summary>{t('console.pairSetup')}</summary>
				<p>{t('console.firstBoss')}</p>
				<CopyBlock text={`hiboss setup --server ${baseUrl.trim()} --bootstrap-secret <secret>`} />
			</details>
		{:else}
			<p role="status">{t('console.checking')}</p>
		{/if}
		{#if error}<p class="error" role="alert">{error}</p>{/if}
		<details>
			<summary>{t('console.differentServer')}</summary>
			<label>
				<span>{t('connect.serverUrl')}</span>
				<input type="url" bind:value={baseUrl} onchange={probe} required />
			</label>
		</details>
		<p class="hint">{t('connect.storedHint')}</p>
	</div>
</main>

<style>
	.screen {
		min-height: 100vh;
		display: grid;
		place-items: center;
		background: var(--hb-bg);
		padding: 1.5rem;
	}
	.card {
		width: 100%;
		max-width: 24rem;
		background: var(--hb-bg-elevated);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 1.5rem;
		display: flex;
		flex-direction: column;
		gap: 0.9rem;
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 0.65rem;
		margin-bottom: 0.25rem;
	}
	.mark {
		width: 32px;
		height: 32px;
		border-radius: var(--hb-radius-sm);
		background: var(--hb-accent);
		color: #0c0e12;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		font-weight: 800;
		font-family: var(--hb-font-mono);
	}
	.name {
		font-weight: 700;
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 12px;
		color: var(--hb-text-muted);
	}
	input {
		background: var(--hb-bg);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius-sm);
		padding: 0.5rem 0.6rem;
		color: var(--hb-text);
		font-family: var(--hb-font);
		font-size: 13px;
	}
	input:focus {
		outline: none;
		border-color: var(--hb-accent);
	}
	button {
		margin-top: 0.25rem;
		background: var(--hb-accent);
		color: #0c0e12;
		border: none;
		border-radius: var(--hb-radius-sm);
		padding: 0.55rem;
		font-weight: 650;
		cursor: pointer;
	}
	button:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}
	.error {
		margin: 0;
		color: var(--hb-priority-critical, tomato);
		font-size: 12px;
	}
	.hint {
		margin: 0;
		font-size: 11px;
		color: var(--hb-text-dim);
	}
	h1 { font: var(--t-title); margin: 0; }
	p { margin: 0; }
	form { display: grid; gap: 8px; }
	input, button, summary { min-height: var(--hit); }
	summary { cursor: pointer; padding-block: 10px; }
	.reachable { color: var(--settled); }
	button.primary { background: var(--ink); color: var(--on-ink); border-color: var(--ink); }
</style>
