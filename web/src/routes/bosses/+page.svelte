<script lang="ts">
	import { onMount } from 'svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';
	import type {
		AgentResponse,
		BossCreateRequest,
		BossRecord,
		BossTokenResponse
	} from '$lib/api/types';
	import { ApiError } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import { toasts } from '$lib/stores/toast.svelte';
	import AccessMatrix from './AccessMatrix.svelte';
	import CreateBossForm from './CreateBossForm.svelte';
	import TokenReveal from './TokenReveal.svelte';
	import { withAccess } from './access-helpers';

	let bosses = $state<BossRecord[]>([]);
	let agents = $state<AgentResponse[]>([]);
	let loading = $state(true);
	let error = $state<string | null>(null);
	let busyKey = $state<string | null>(null);
	let creating = $state(false);
	let revealed = $state<BossTokenResponse | null>(null);

	function errMsg(e: unknown): string {
		return e instanceof ApiError ? `${e.status}: ${e.body || e.message}` : String(e);
	}

	async function load() {
		const client = auth.client;
		if (!client) {
			error = 'Not connected';
			loading = false;
			return;
		}
		loading = true;
		error = null;
		try {
			const [bossRes, agentRes] = await Promise.all([client.bosses(), client.agents()]);
			bosses = bossRes.bosses ?? [];
			agents = agentRes.agents ?? [];
		} catch (e) {
			error = errMsg(e);
		} finally {
			loading = false;
		}
	}

	async function onToggle(bossId: string, agentId: string, next: boolean) {
		const client = auth.client;
		if (!client) {
			toasts.push('Not connected', 'error');
			return;
		}
		const key = `${bossId}:${agentId}`;
		if (busyKey) return;
		busyKey = key;
		const prev = bosses;
		bosses = withAccess(bosses, bossId, agentId, next);
		try {
			if (next) await client.grantAccess(bossId, agentId);
			else await client.revokeAccess(bossId, agentId);
			toasts.push(next ? 'Access granted' : 'Access revoked', 'success');
		} catch (e) {
			bosses = prev;
			toasts.push(errMsg(e), 'error');
		} finally {
			busyKey = null;
		}
	}

	async function onRotate(bossId: string) {
		const client = auth.client;
		if (!client) {
			toasts.push('Not connected', 'error');
			return;
		}
		const key = `rotate:${bossId}`;
		if (busyKey) return;
		busyKey = key;
		try {
			const res = await client.rotateToken(bossId);
			revealed = res;
			toasts.push(`Token rotated for ${res.name}`, 'success');
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			busyKey = null;
		}
	}

	async function onCreate(body: BossCreateRequest) {
		const client = auth.client;
		if (!client) {
			toasts.push('Not connected', 'error');
			return;
		}
		creating = true;
		try {
			const created = await client.createBoss(body);
			bosses = [created, ...bosses];
			toasts.push(`Created boss ${created.name}`, 'success');
		} catch (e) {
			toasts.push(errMsg(e), 'error');
		} finally {
			creating = false;
		}
	}

	onMount(() => {
		void load();
	});
</script>

<section class="bosses">
	<header class="head">
		<div>
			<h1>Bosses & Access</h1>
			<p class="sub">权限 — boss roles, channel bindings, and agent access matrix</p>
		</div>
		<button type="button" class="refresh" onclick={() => load()} disabled={loading}>Refresh</button>
	</header>

	{#if revealed}
		<TokenReveal
			bossName={revealed.name}
			token={revealed.token}
			onDismiss={() => (revealed = null)}
		/>
	{/if}

	{#if error}
		<ErrorState message={error} onRetry={load} />
	{:else if loading && bosses.length === 0}
		<div class="panel"><Skeleton rows={6} /></div>
	{:else}
		<CreateBossForm busy={creating} {onCreate} />

		{#if bosses.length === 0}
			<EmptyState
				title="No bosses yet"
				detail="Create a boss to manage roles, bindings, and agent access."
			/>
		{:else}
			{#if agents.length === 0}
				<p class="hint">No agents in scope yet — grant columns appear when agents are accessible.</p>
			{/if}
			<AccessMatrix {bosses} {agents} {busyKey} {onToggle} {onRotate} />
		{/if}
	{/if}
</section>

<style>
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
	.sub {
		margin: 0.15rem 0 0;
		color: var(--hb-text-muted);
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
</style>
