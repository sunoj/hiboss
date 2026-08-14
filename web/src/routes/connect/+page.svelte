<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { DEFAULT_BASE_URL } from '$lib/api/auth';
	import { i18n, LOCALES, t, type Locale } from '$lib/i18n';

	let baseUrl = $state(DEFAULT_BASE_URL);
	let token = $state('');
	let connecting = $state(false);
	let error = $state<string | null>(null);

	async function submit(event: Event): Promise<void> {
		event.preventDefault();
		if (connecting) return;
		connecting = true;
		error = null;
		try {
			await auth.connect(baseUrl.trim(), token.trim());
			await goto('/');
		} catch (err) {
			error = err instanceof Error ? err.message : String(err);
		} finally {
			connecting = false;
		}
	}

	function selectLocale(event: Event): void {
		const value = (event.currentTarget as HTMLSelectElement).value;
		if ((LOCALES as readonly string[]).includes(value)) i18n.setLocale(value as Locale);
	}
</script>

<div class="screen">
	<form class="card" onsubmit={submit}>
		<div class="brand">
			<span class="mark">hb</span>
			<div>
				<div class="name">{t('app.title')}</div>
				<div class="sub">{t('brand.subtitle')}</div>
			</div>
			<label class="language">
				<span class="sr-only">{t('language.label')}</span>
				<select value={i18n.locale} onchange={selectLocale} aria-label={t('language.label')}>
					<option value="en">{t('language.en')}</option>
					<option value="zh-CN">{t('language.zh')}</option>
					<option value="ja">{t('language.ja')}</option>
					<option value="ko">{t('language.ko')}</option>
				</select>
			</label>
		</div>

		<label>
			<span>{t('connect.serverUrl')}</span>
			<input
				type="url"
				bind:value={baseUrl}
				placeholder="https://your-hiboss-server.workers.dev"
				autocomplete="off"
				required
			/>
		</label>

		<label>
			<span>{t('connect.bossToken')}</span>
			<input
				type="password"
				bind:value={token}
				placeholder="hb_boss_…"
				autocomplete="off"
				required
			/>
		</label>

		{#if error}
			<p class="error" role="alert">{error}</p>
		{/if}

		<button type="submit" disabled={connecting || !token.trim()}>
			{connecting ? t('connect.connecting') : t('connect.connect')}
		</button>

		<p class="hint">{t('connect.storedHint')}</p>
	</form>
</div>

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
	.language {
		margin-left: auto;
	}
	.language select {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg);
		border-radius: var(--hb-radius-sm);
		padding: 0.25rem 0.35rem;
		color: var(--hb-text-muted);
		font: inherit;
		font-size: 11px;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
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
	.sub {
		font-size: 12px;
		color: var(--hb-text-dim);
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
</style>
