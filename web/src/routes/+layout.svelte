<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import favicon from '$lib/assets/favicon.svg';
	import '$lib/design/tokens.css';
	import AppShell from '$lib/components/AppShell.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { DEFAULT_BASE_URL } from '$lib/api/auth';
	import { initLocale, t } from '$lib/i18n';

	let { children } = $props();

	onMount(() => {
		initLocale();
		auth.hydrate();
		document.documentElement.setAttribute('data-theme', 'dark');
		const path = $page.url.pathname;
		if (!auth.isAuthenticated && path !== '/connect') {
			void goto('/connect');
		} else if (auth.isAuthenticated && path === '/connect') {
			void goto('/');
		}
	});

	$effect(() => {
		if (!auth.ready) return;
		const path = $page.url.pathname;
		if (!auth.isAuthenticated && path !== '/connect') {
			void goto('/connect');
		}
	});
</script>

<svelte:head>
	<title>{t('app.title')}</title>
	<link rel="icon" href={favicon} />
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link
		href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"
		rel="stylesheet"
	/>
	<meta name="description" content={t('app.title')} />
</svelte:head>

{#if !auth.ready}
	<div class="boot">{t('app.loading')}</div>
{:else if !auth.isAuthenticated}
	{@render children()}
{:else}
	<AppShell connected={true}>
		{@render children()}
	</AppShell>
{/if}

<style>
	.boot {
		min-height: 100vh;
		display: grid;
		place-items: center;
		color: var(--hb-text-muted);
		font-family: var(--hb-font);
	}
</style>
