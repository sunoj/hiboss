<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';

	interface Props {
		connected: boolean;
	}

	let { connected }: Props = $props();

	const bossName = $derived(auth.connection?.boss?.name ?? '—');
	const baseUrl = $derived(auth.connection?.baseUrl ?? '');

	function signOut() {
		auth.signOut();
		void goto('/connect');
	}
</script>

<header class="top">
	<div class="status">
		<span class="light" class:on={connected} aria-hidden="true"></span>
		<span>{connected ? 'Connected' : 'Offline'}</span>
		{#if baseUrl}
			<span class="url" title={baseUrl}>{baseUrl.replace(/^https?:\/\//, '')}</span>
		{/if}
	</div>
	<div class="right">
		<span class="boss">{bossName}</span>
		<button type="button" onclick={signOut}>Sign out</button>
	</div>
</header>

<style>
	.top {
		height: var(--hb-topbar-height);
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		padding: 0 1rem;
		border-bottom: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		position: sticky;
		top: 0;
		z-index: 10;
	}
	.status {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		min-width: 0;
		color: var(--hb-text-muted);
	}
	.light {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--hb-text-dim);
		flex-shrink: 0;
	}
	.light.on {
		background: var(--hb-success);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--hb-success) 25%, transparent);
	}
	.url {
		font-family: var(--hb-font-mono);
		font-size: 11px;
		color: var(--hb-text-dim);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.right {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		flex-shrink: 0;
	}
	.boss {
		font-weight: 600;
	}
	button {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-panel);
		border-radius: var(--hb-radius-sm);
		padding: 0.25rem 0.55rem;
		cursor: pointer;
		color: var(--hb-text-muted);
	}
	button:hover {
		color: var(--hb-text);
		background: var(--hb-bg-hover);
	}
</style>
