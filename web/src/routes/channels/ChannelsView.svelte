<!-- Channels console with optimistic notification toggles.
     Depends on boss API, auth, i18n, and grouped channel components. -->
<script lang="ts">
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type { BossChannelConfig } from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import AgentChannelGroup from './AgentChannelGroup.svelte';
	import { groupChannelsByAgent } from './groupChannels';

	let { agentId }: { agentId?: string } = $props();
	let channels = $state<BossChannelConfig[]>([]);
	const loadState = new LoadState();
	let pending = $state<Record<string, boolean>>({});
	let errors = $state<Record<string, string>>({});
	let warnings = $state<Record<string, boolean>>({});

	const groups = $derived(groupChannelsByAgent(channels));
	const saving = $derived(Object.values(pending).some(Boolean));
	const readOnly = $derived(auth.connection?.boss?.role === 'viewer');

	async function toggle(channel: BossChannelConfig): Promise<void> {
		if (loadState.loading || readOnly || pending[channel.agent_id]) return;
		const client = auth.client;
		if (!client) { errors[channel.id] = t('top.offline'); return; }
		pending[channel.agent_id] = true;
		errors[channel.id] = '';
		const enabled = channel.enabled !== 1;
		channels = channels.map((row) => row.id === channel.id ? { ...row, enabled: Number(enabled) } : row);
		try {
			const { warning, ...updated } = await client.updateChannel(channel.id, enabled);
			channels = channels.map((row) => row.id === channel.id ? updated : row);
			for (const row of channels.filter((row) => row.agent_id === channel.agent_id)) warnings[row.id] = false;
			warnings[channel.id] = Boolean(warning);
		} catch (e) {
			channels = channels.map((row) => row.id === channel.id ? channel : row);
			errors[channel.id] = `${t('channel.updateFailed')}: ${e instanceof ApiError ? e.body || e.message : String(e)}`;
		} finally {
			pending[channel.agent_id] = false;
		}
	}

	async function load() {
		if (saving) return;
		await loadState.run(async (client) => {
			const all = await client.channels();
			channels = agentId ? all.filter((channel) => channel.agent_id === agentId) : all;
			errors = {};
			warnings = {};
		});
	}

	onMount(() => {
		void load();
	});
</script>

<section class="page">
	<header class="head">
		<div>
			{#if agentId}<h2>{t('page.channels')}</h2>{:else}<h1>{t('page.channels')}</h1>{/if}
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loadState.loading || saving}>
			{t('common.refresh')}
		</button>
	</header>

	<p class="cli-note" role="note">{t('channel.cliNote')}</p>

	{#if loadState.error}
		<ErrorState message={loadState.error} onRetry={load} />
	{:else if loadState.loading && channels.length === 0}
		<div class="board">
			{#each Array(3) as _, i (i)}
				<div class="skel"><Skeleton rows={4} height="1.2rem" /></div>
			{/each}
		</div>
	{:else if channels.length === 0}
		<EmptyState
			title={t('page.noChannels')}
			detail={t('page.noChannelsDetail')}
		/>
	{:else}
		<div class="board" role="list">
			{#each groups as group (group.agent_id)}
				<div role="listitem">
					<AgentChannelGroup
						{group} {errors} {warnings}
						disabled={loadState.loading || readOnly || pending[group.agent_id]}
						onToggle={toggle}
					/>
				</div>
			{/each}
		</div>
	{/if}
</section>

<style>
	/* Page headings and refresh controls shared by the console routes.
 * Inlined by vitePreprocess so each consuming component retains scoped selectors. */
.head {
	display: flex;
	justify-content: space-between;
	align-items: flex-start;
	gap: 1rem;
	margin-bottom: 1rem;
}
h1 {
	margin: 0;
	font-size: 1.25rem;
	font-weight: 700;
	letter-spacing: -0.02em;
}
.refresh {
	border: 1px solid var(--hb-border);
	background: var(--hb-bg-panel);
	border-radius: var(--hb-radius-sm);
	padding: 0.35rem 0.7rem;
	cursor: pointer;
}
.refresh:disabled {
	opacity: 0.6;
	cursor: wait;
}
	.head {
		margin-bottom: 0.65rem;
	}

	.cli-note {
		margin: 0 0 1rem;
		padding: 0.45rem 0.65rem;
		font-size: 12px;
		color: var(--hb-text-muted);
		background: var(--hb-bg-input);
		border: 1px solid var(--hb-border-subtle);
		border-radius: var(--hb-radius-sm);
	}
	.board {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
		gap: 0.75rem;
	}
	.skel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
	}
</style>
