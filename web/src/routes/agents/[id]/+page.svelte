<!-- Agent details on their own address.
     Reuses the key and sending-defaults forms. -->
<script lang="ts">
	import { page } from '$app/state';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import { apiErrorMessage, type AgentResponse } from '$lib/api/types';
	import AgentDrawer from '../AgentDrawer.svelte';
	import ChannelsView from '../../channels/ChannelsView.svelte';

	let agent = $state<AgentResponse | null>(null);
	let error = $state('');
	let generation = 0;

	async function load(id: string) {
		const request = ++generation;
		try {
			const result = await auth.client?.agents();
			if (request === generation) agent = result?.agents.find((row) => row.id === id) ?? null;
		} catch (failure) {
			if (request === generation) error = apiErrorMessage(failure);
		}
	}

	$effect(() => {
		agent = null; error = '';
		void load(page.params.id ?? '');
	});
</script>

<section>
	{#if error}<p role="alert">{error}</p>
	{:else if agent}
		{#key agent.id}
			<AgentDrawer {agent} />
			<ChannelsView agentId={agent.id} />
		{/key}
	{:else}
		<p role="status">{t('app.loading')}</p>
	{/if}
</section>
