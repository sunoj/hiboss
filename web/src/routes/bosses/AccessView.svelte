<script lang="ts">
	import { onMount } from 'svelte';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type {
		AgentResponse,
		BossCreateRequest,
		BossRecord, BossRole,
		BossTokenResponse
	} from '$lib/api/types';
	import { apiErrorMessage } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import { toasts } from '$lib/stores/toast.svelte';
	import PeopleList from './PeopleList.svelte';
	import AccessMatrix from './AccessMatrix.svelte';
	import CreateBossForm from './CreateBossForm.svelte';
	import TokenReveal from './TokenReveal.svelte';
	import { withAccess } from './access-helpers';

	let bosses = $state<BossRecord[]>([]);
	let agents = $state<AgentResponse[]>([]);
	const loadState = new LoadState();
	let busyKey = $state<string | null>(null);
	let creating = $state(false);
	let showCreate = $state(false);
	let accessError = $state('');
	const admin = $derived(auth.connection?.boss?.role === 'admin');
	let revealed = $state<BossTokenResponse | null>(null);

	async function load() {
		await loadState.run(async (client) => {
			const [bossRes, agentRes] = await Promise.all([client.bosses(), client.agents()]);
			bosses = bossRes.bosses ?? [];
			agents = agentRes.agents ?? [];
		});
	}

	async function onToggle(bossId: string, agentId: string, next: boolean) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		const key = `${bossId}:${agentId}`;
		if (busyKey) return;
		accessError = '';
		busyKey = key;
		const prev = bosses;
		bosses = withAccess(bosses, bossId, agentId, next);
		try {
			if (next) await client.grantAccess(bossId, agentId);
			else await client.revokeAccess(bossId, agentId);
			toasts.push(next ? t('form.accessGranted') : t('form.accessRevoked'), 'success');
		} catch (e) {
			bosses = prev;
			accessError = apiErrorMessage(e);
		} finally {
			busyKey = null;
		}
	}

	async function onRotate(bossId: string) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		const key = `rotate:${bossId}`;
		if (busyKey) return;
		busyKey = key;
		try {
			const res = await client.rotateToken(bossId);
			if (auth.connection?.boss?.id === bossId) auth.replaceToken(res.token);
			revealed = res;
			toasts.push(t('form.tokenRotated', { name: res.name }), 'success');
		} catch (e) {
			toasts.push(apiErrorMessage(e), 'error');
		} finally {
			busyKey = null;
		}
	}

	async function onCreate(body: BossCreateRequest) {
		const client = auth.client;
		if (!client) {
			toasts.push(t('top.offline'), 'error');
			return;
		}
		creating = true;
		try {
			const created = await client.createBoss(body);
			bosses = [created, ...bosses];
			showCreate = false;
			revealed = await client.rotateToken(created.id);
		} catch (e) {
			toasts.push(apiErrorMessage(e), 'error');
		} finally {
			creating = false;
		}
	}

	async function changeRole(id: string, role: BossRole) {
		const client = auth.client;
		if (!client || busyKey) return;
		busyKey = id;
		accessError = '';
		try {
			const updated = await client.updateBoss(id, { role });
			bosses = bosses.map((boss) => boss.id === id ? { ...boss, ...updated } : boss);
		} catch (failure) {
			accessError = apiErrorMessage(failure);
		} finally {
			busyKey = null;
		}
	}

	async function archive(id: string, archived: boolean) {
		const client = auth.client;
		if (!client || busyKey) return;
		busyKey = id;
		accessError = '';
		try {
			await client.setBossArchived(id, archived);
			await load();
		} catch (failure) {
			accessError = apiErrorMessage(failure);
		} finally {
			busyKey = null;
		}
	}

	onMount(() => {
		if (admin) void load();
	});
</script>

<section class="bosses">
	<header class="head">
		<div>
			<h1>{t('page.bosses')}</h1>
		</div>
		{#if admin}
			<button class="add" type="button" aria-expanded={showCreate} onclick={() => { showCreate = !showCreate; }}>
				{t('console.addPerson')}
			</button>
		{/if}
	</header>

	{#if revealed}
		<TokenReveal
			bossName={revealed.name}
			token={revealed.token}
			onDismiss={() => (revealed = null)}
		/>
	{/if}

	{#if accessError}<p role="alert">{accessError}</p>{/if}
	{#if !admin}
		<p>{t('console.forbidden')}</p>
	{:else if loadState.error}
		<ErrorState message={loadState.error} onRetry={load} />
	{:else if loadState.loading && bosses.length === 0}
		<div class="panel"><Skeleton rows={6} /></div>
	{:else}
		{#if showCreate}<CreateBossForm busy={creating} {onCreate} />{/if}

		{#if bosses.length === 0}
			<EmptyState
			title={t('page.noBosses')}
			detail={t('page.noBossesDetail')}
			/>
		{:else}
			{#if agents.length === 0}
				<p class="hint">{t('page.noAgentsInScope')}</p>
			{/if}
			<PeopleList {bosses} busy={busyKey !== null} {onRotate} onRole={changeRole} onArchive={archive} />
			<h2>{t('console.agentAccess')}</h2>
			<AccessMatrix bosses={bosses.filter(({ archived_at }) => !archived_at)} {agents} {busyKey} {onToggle} />
		{/if}
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
	font: var(--t-large);
	letter-spacing: -0.02em;
}

	.panel {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
		margin-bottom: 0.75rem;
	}
	.hint {
		margin: 0 0 0.65rem;
		color: var(--hb-text-muted);
		font-size: 12px;
	}
	.add { min-height: var(--hit); background: var(--ink); color: var(--on-ink);
		border-radius: var(--r-s); border: 0; padding-inline: 12px; }
</style>
