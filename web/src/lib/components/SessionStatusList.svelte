<script lang="ts">
	import { sessionStatusEntries } from '$lib/api/mappers';
	import { coerceSessionStatus, sessionColor, sessionLabel } from '$lib/design/semantics';

	interface Props {
		counts: Record<string, number>;
	}

	let { counts }: Props = $props();
	const rows = $derived(sessionStatusEntries(counts));
</script>

<ul class="list">
	{#each rows as row (row.status)}
		{@const color = sessionColor(coerceSessionStatus(row.status))}
		<li>
			<span class="dot" style:background={color}></span>
			<span class="status">{sessionLabel(coerceSessionStatus(row.status))}</span>
			<span class="count">{row.count}</span>
		</li>
	{/each}
</ul>

<style>
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
	}
	li {
		display: grid;
		grid-template-columns: 12px 1fr auto;
		gap: 0.5rem;
		align-items: center;
	}
	.dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
	}
	.status {
		text-transform: capitalize;
		color: var(--hb-text-muted);
	}
	.count {
		font-variant-numeric: tabular-nums;
		font-weight: 600;
	}
</style>
