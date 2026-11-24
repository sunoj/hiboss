<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/stores';
	import favicon from '$lib/assets/favicon.svg';
	import '$lib/design/tokens.css';
	import AppShell from '$lib/components/AppShell.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { inputs } from '$lib/decisions/inputs.svelte';
	import { initLocale, t } from '$lib/i18n';

	let { children } = $props();

	onMount(() => {
		initLocale();
		auth.hydrate();
		const theme = localStorage.getItem('hiboss.web.appearance');
		if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
		const path = $page.url.pathname;
		if (!auth.isAuthenticated && path !== '/connect') {
			void goto('/connect');
		} else if (auth.isAuthenticated && path === '/connect') {
			void goto('/');
		}
	});

	$effect(() => auth.client ? inputs.watch(auth.client) : undefined);

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
	<meta name="description" content={t('app.title')} />
</svelte:head>

{#if !auth.ready}
	<div class="boot">{t('app.loading')}</div>
{:else if !auth.isAuthenticated}
	{@render children()}
{:else}
	<AppShell>
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
