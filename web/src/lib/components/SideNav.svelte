<!-- Console module navigation with active-route and translated labels.
     Depends on shared navigation definitions, page state, and i18n. -->
<script lang="ts">
	import ConsoleIcon from './ConsoleIcon.svelte';
	import { page } from '$app/stores';
	import { t } from '$lib/i18n';
	import { auth } from '$lib/stores/auth.svelte';
	import { inputs } from '$lib/decisions/inputs.svelte';
	import { NAV_MODULES, isActivePath } from '$lib/nav';
	let { tabHeight = $bindable(0) }: { tabHeight?: number } = $props();
	const openCount = $derived(inputs.messages.filter(({ id }) => !inputs.settled.has(id)).length);
</script>

<aside class="nav" aria-label={t('nav.aria')}>
	<div class="brand">
		<span class="mark">hb</span>
		<div>
			<div class="name">hiboss</div>
			<div class="sub">{t('brand.console')}</div>
		</div>
	</div>
	<nav>
		{#each NAV_MODULES as mod (mod.id)}
			{#if mod.id === 'agents'}<span class="section">{t('console.manage')}</span>{/if}
			{#if mod.id === 'access'}<span class="section">{t('console.system')}</span>{/if}
			{#if mod.id !== 'access' || auth.connection?.boss?.role === 'admin'}
				<a href={mod.href} aria-current={isActivePath($page.url.pathname, mod.href) ? 'page' : undefined}>
					<ConsoleIcon name={mod.id} />{t(mod.labelKey)}
					{#if mod.id === 'today' && inputs.loaded && openCount}
						<span class="count">{openCount}</span>
					{/if}
				</a>
			{/if}
		{/each}
	</nav>
	<footer>
		{t(inputs.connected ? 'top.connected' : 'top.offline')}
		<span>{auth.connection?.baseUrl}</span>
	</footer>
</aside>

<nav class="tabs" bind:clientHeight={tabHeight} aria-label={t('nav.aria')}>
	{#each NAV_MODULES.filter((module) => module.primary) as mod (mod.id)}
		<a href={mod.href} aria-current={isActivePath($page.url.pathname, mod.href) ? 'page' : undefined}>
			<ConsoleIcon name={mod.id} />
			{t(mod.shortKey)}
		</a>
	{/each}
	<a href="/more" aria-current={$page.url.pathname === '/more' ? 'page' : undefined}><ConsoleIcon name="more" />{t('console.more')}</a>
</nav>

<style>
	.nav { display: none; }
	.tabs {
		position: fixed;
		inset: auto 0 0;
		z-index: 20;
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		background: var(--surface);
		border-top: 1px solid var(--hairline);
		padding-bottom: env(safe-area-inset-bottom);
	}
	a { display: flex; align-items: center; min-height: var(--hit); padding: 8px 12px; gap: 10px; border-radius: var(--r-s); }
	.tabs a { display: grid; justify-items: center; align-content: center; gap: 2px; min-height: calc(var(--bottom-tabs) - 1px);
		padding-inline: 2px; text-align: center; font: var(--t-caption); color: var(--text-2); }
	.tabs a[aria-current="page"] { color: var(--ink); font-weight: 600; background: var(--surface); }
	a:hover, a[aria-current="page"] { background: var(--live-soft); color: var(--live); }
	@media (min-width: 1024px) {
		.tabs { display: none; }
		.nav {
			display: flex; flex-direction: column; flex: 0 0 var(--sidebar);
			position: sticky; top: 0; height: 100dvh; overflow: auto;
			background: var(--surface); border-inline-end: 1px solid var(--hairline); padding: 16px;
		}
		.brand { display: flex; align-items: center; gap: 10px; margin-block-end: 24px; }
		.mark { display: grid; place-items: center; border-radius: 8px; background: var(--ink);
			color: var(--on-ink); width: 32px; height: 32px; font-weight: 700; }
		.name { font: var(--t-headline); }
		.sub, footer { color: var(--text-3); font: var(--t-caption); }
		.count { margin-inline-start: auto; background: var(--signal-soft); color: var(--signal);
			padding: 2px 8px; border-radius: var(--r-pill); }
		.section { display: block; margin: 20px 12px 4px; font: var(--t-caption); color: var(--text-3); }
		footer { margin-top: auto; padding: 12px; overflow-wrap: anywhere; }
		footer span { display: block; }
	}
</style>
