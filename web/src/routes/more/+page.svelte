<!-- Mobile navigation for administration and account settings.
     Shares the sidebar's route definitions. -->
<script lang="ts">
	import AccountActions from '$lib/components/AccountActions.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { NAV_MODULES } from '$lib/nav';
	import { t } from '$lib/i18n';
</script>

<h1>{t('console.more')}</h1>
<nav aria-label={t('nav.aria')}>
	{#each NAV_MODULES.filter((module) => !module.primary) as module (module.id)}
		{#if module.id === 'agents'}<h2>{t('console.manage')}</h2>{/if}
		{#if module.id === 'access'}<h2>{t('console.system')}</h2>{/if}
		{#if module.id !== 'access' || auth.connection?.boss?.role === 'admin'}
			<a href={module.href}>{t(module.labelKey)}</a>
		{/if}
	{/each}
</nav>
<AccountActions />

<style>
	h1 { font: var(--t-large); }
	h2 { font: var(--t-headline); }
	a { display: flex; align-items: center; min-height: var(--hit); padding: 8px 12px;
		background: var(--surface); border-bottom: 1px solid var(--hairline); }
	nav { margin-bottom: 16px; }
</style>
