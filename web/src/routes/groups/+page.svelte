<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type {
		AgentResponse,
		BroadcastGroupRequest,
		CreateGroupRequest,
		GroupResponse
	} from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import { toasts } from '$lib/stores/toast.svelte';
	import BroadcastComposer from './BroadcastComposer.svelte';
	import CreateGroupForm from './CreateGroupForm.svelte';
	import GroupCard from './GroupCard.svelte';
	import { broadcastResultLabel, sortGroupsByName } from './groupHelpers';

	let groups = $state<GroupResponse[]>([]);
	let agents = $state<AgentResponse[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let creating = $state(false);
	let busyKey = $state<string | null>(null);

	const sorted = $derived(sortGroupsByName(groups));

	function errMsg(e: unknown): string {
		return e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
	}

	async function load() {
		const client = auth.client;
		if (!client) {
			error = t('top.offline');
			loading = false;
			return;
		}
		loading = true;
		error = null;
		try {
			const [groupRes, agentRes] = await Promise.all([client.groups(), client.agents()]);
			groups = groupRes.groups ?? [];
			agents = agentRes.agents ?? [];
		} catch (e) {
			error = errMsg(e);
		} finally {
			loading = false;
		}
	}

	async function onCreate(body: CreateGroupRequest) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		creating = true;
		try {
			const created = await client.createGroup(body);
			toasts.push(t('form.createdGroup', { name: created.name }), 'success');
			await load();
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			creating = false;
		}
	}

	async function onDelete(groupId: string) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		const key = `del:${groupId}`;
		if (busyKey) return;
		busyKey = key;
		try {
			await client.deleteGroup(groupId);
			toasts.push(t('form.groupDeleted'), 'success');
			await load();
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			busyKey = null;
		}
	}

	async function onAddMember(groupId: string, agentId: string) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		const key = `add:${groupId}:${agentId}`;
		if (busyKey) return;
		busyKey = key;
		try {
			await client.addGroupMember(groupId, { agent_id: agentId });
			toasts.push(t('form.memberAdded'), 'success');
			await load();
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			busyKey = null;
		}
	}

	async function onRemoveMember(groupId: string, agentId: string) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		const key = `rm:${groupId}:${agentId}`;
		if (busyKey) return;
		busyKey = key;
		try {
			await client.removeGroupMember(groupId, agentId);
			toasts.push(t('form.memberRemoved'), 'success');
			await load();
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			busyKey = null;
		}
	}

	async function onBroadcast(groupId: string, body: BroadcastGroupRequest) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		const key = `bc:${groupId}`;
		if (busyKey) return;
		busyKey = key;
		try {
			const res = await client.broadcastGroup(groupId, body);
			const count = res.count ?? res.messages?.length ?? 0;
			toasts.push(broadcastResultLabel(count), 'success');
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			busyKey = null;
		}
	}

	onMount(() => {
		void load();
	});
</script>

<section class="page">
	<header class="head">
		<div>
			<h1>{t('page.groups')}</h1>
			<p class="sub">{t('page.groupsSub')}</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>
			{t('common.refresh')}
		</button>
	</header>

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && groups.length === 0}
		<div class="layout">
			<div class="grid">
				{#each Array(4) as _, i (i)}
					<div class="skel"><Skeleton rows={4} height="1.2rem" /></div>
				{/each}
			</div>
			<div class="skel composer-skel"><Skeleton rows={6} /></div>
		</div>
	{:else}
		<CreateGroupForm {agents} busy={creating} {onCreate} />

		<div class="layout">
			<div class="main">
				{#if sorted.length === 0}
					<EmptyState
						title={t('page.noGroups')}
						detail={t('page.noGroupsDetail')}
					/>
				{:else}
					<div class="grid" role="list">
						{#each sorted as group (group.id)}
							<div role="listitem">
								<GroupCard
									{group}
									{agents}
									busy={busyKey !== null}
									{onDelete}
									{onAddMember}
									{onRemoveMember}
								/>
							</div>
						{/each}
					</div>
				{/if}
			</div>
			<aside class="side">
				<BroadcastComposer
					groups={sorted}
					busy={busyKey?.startsWith('bc:') ?? false}
					{onBroadcast}
				/>
			</aside>
		</div>
	{/if}
</section>

<style>
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 1rem;
		margin-bottom: 0.85rem;
	}
	h1 {
		margin: 0;
		font-size: 1.25rem;
		font-weight: 700;
		letter-spacing: -0.02em;
	}
	.sub {
		margin: 0.15rem 0 0;
		color: var(--hb-text-muted);
	}
	.refresh {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-panel);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.7rem;
		font: inherit;
		font-size: 12px;
		color: var(--hb-text);
		cursor: pointer;
		flex-shrink: 0;
	}
	.refresh:disabled {
		opacity: 0.6;
		cursor: wait;
	}
	.layout {
		display: grid;
		grid-template-columns: minmax(0, 1.6fr) minmax(240px, 0.9fr);
		gap: 0.75rem;
		align-items: start;
	}
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
		gap: 0.75rem;
	}
	.skel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
	}
	.composer-skel {
		min-height: 12rem;
	}
	@media (max-width: 900px) {
		.layout {
			grid-template-columns: 1fr;
		}
	}
</style>
