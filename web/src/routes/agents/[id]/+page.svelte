<!-- Agent details on their own address.
     Reuses the key and sending-defaults forms. -->
<script lang="ts">
	import { page } from '$app/state';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import { agentDirectory } from '$lib/stores/agents.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import { apiErrorMessage } from '$lib/api/types';
	import AgentDrawer from '../AgentDrawer.svelte';

	const agent = $derived(agentDirectory.rows.find((row) => row.id === page.params.id));
	let error = $state('');

	async function load() {
		error = '';
		try { await agentDirectory.load(auth.client); }
		catch (failure) { error = apiErrorMessage(failure); }
	}

	$effect(() => { void load(); });
</script>

<section>
	{#if error}<ErrorState message={error} onRetry={load} />
	{:else if agent}
		{#key agent.id}
			<AgentDrawer {agent} />
		{/key}
	{:else if agentDirectory.loaded}
		<p>{t('page.noAgents')}</p>
	{:else}
		<p role="status">{t('app.loading')}</p>
	{/if}
</section>
