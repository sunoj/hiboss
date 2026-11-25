<!-- Saves optional agent admin capability through the authenticated config API.
     Rendered only for admin bosses on servers that advertise the field. -->
<script lang="ts">
	import { auth } from '$lib/stores/auth.svelte';
	import { agentDirectory } from '$lib/stores/agents.svelte';
	import { canSetAgentAdmin } from '$lib/api/agent-capabilities';
	import { apiErrorMessage, type AgentResponse } from '$lib/api/types';
	import { t } from '$lib/i18n';

	let { agent }: { agent: AgentResponse } = $props();
	let busy = $state(false);
	let error = $state('');

	async function toggle() {
		const client = auth.client;
		if (!client || busy || !canSetAgentAdmin(agent, auth.connection?.boss?.role)) return;
		const id = agent.id;
		const admin = !agent.admin;
		busy = true;
		error = '';
		try {
			const updated = await client.updateAgentConfig(id, { admin });
			agentDirectory.update(client, id, { admin: updated?.admin ?? admin });
		} catch (failure) {
			error = apiErrorMessage(failure);
		} finally {
			busy = false;
		}
	}
</script>

<label>
	<input type="checkbox" role="switch" checked={agent.admin} disabled={busy}
		onchange={(event) => { event.currentTarget.checked = !!agent.admin; void toggle(); }} />
	{t('console.adminCapability')}
</label>
{#if error}<p role="alert">{error}</p>{/if}

<style>
	label { display: inline-flex; align-items: center; min-height: var(--hit); gap: 8px; }
	p { color: var(--danger); margin: 0; }
</style>
