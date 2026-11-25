<!-- Connection state and age of the last successful snapshot.
     Visual ticks stay outside live regions to avoid repeated announcements. -->
<script lang="ts">
	import { inputs } from '$lib/decisions/inputs.svelte';
	import { formatDateTime, getLocale, t } from '$lib/i18n';

	let { updatedAt, status }: { updatedAt: number | null; status: 'connecting' | 'online' | 'offline' } = $props();
	const age = $derived(updatedAt === null ? 0 : Math.max(0, Math.floor((inputs.now - updatedAt) / 1000)));
	const freshness = $derived(new Intl.NumberFormat(getLocale(), {
		style: 'unit', unit: age < 60 ? 'second' : 'minute', unitDisplay: 'narrow'
	}).format(age < 60 ? age : Math.floor(age / 60)));
</script>

<span class="freshness" class:offline={status === 'offline'}>
	{t(status === 'online' ? 'top.connected' : status === 'connecting' ? 'connect.connecting' : 'top.offline')}
	{#if updatedAt !== null}
		{@const timestamp = new Date(updatedAt).toISOString()}
		· <time datetime={timestamp} title={formatDateTime(timestamp)}>{t('console.lastUpdated', { time: freshness })}</time>
	{/if}
</span>

<style>
	.freshness { display: inline-block; border-radius: var(--r-pill); background: var(--surface);
		padding: 6px 12px; font: var(--t-footnote); }
	.offline { background: var(--signal-soft); color: var(--signal); }
</style>
