<!-- Delivery tabs share the existing destination, routing, and provider operations.
     The selected tab has an addressable URL. -->
<script lang="ts">
	import { page } from '$app/state';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import NotificationsView from '../notifications/NotificationsView.svelte';
	import RulesView from '../routing/RulesView.svelte';

	const tab = $derived(page.url.searchParams.get('tab'));
</script>

<h1>{t('console.delivery')}</h1>
<nav class="section-tabs" aria-label={t('console.delivery')}>
	<a href="/delivery" aria-current={!tab ? 'page' : undefined}>{t('console.destinations')}</a>
	<a href="/delivery?tab=rules" aria-current={tab === 'rules' ? 'page' : undefined}>{t('console.rules')}</a>
	{#if auth.connection?.boss?.role === 'admin'}
		<a href="/delivery?tab=providers" aria-current={tab === 'providers' ? 'page' : undefined}>
			{t('console.providers')}
		</a>
	{/if}
</nav>
{#if tab === 'rules'}
	<RulesView embedded />
{:else}
	<NotificationsView embedded providersOnly={tab === 'providers' && auth.connection?.boss?.role === 'admin'} />
{/if}

<style>
	@import '../../lib/design/section-tabs.css';
	h1 { margin: 0 0 12px; }
</style>
