<script lang="ts">
	import { priorityBarWidths } from '$lib/api/mappers';
	import { priorityColor, type Priority } from '$lib/design/semantics';

	interface Props {
		distribution: Record<Priority, number>;
	}

	let { distribution }: Props = $props();
	const bars = $derived(priorityBarWidths(distribution));
</script>

<div class="bars" role="list" aria-label="Priority distribution">
	{#each bars as bar (bar.priority)}
		<div class="row" role="listitem">
			<span class="label" style:color={priorityColor(bar.priority)}>{bar.priority}</span>
			<div class="track">
				<div
					class="fill"
					style:width="{bar.pct}%"
					style:background={priorityColor(bar.priority)}
				></div>
			</div>
			<span class="count">{bar.count}</span>
		</div>
	{/each}
</div>

<style>
	.bars {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
	}
	.row {
		display: grid;
		grid-template-columns: 64px 1fr 36px;
		gap: 0.5rem;
		align-items: center;
	}
	.label {
		font-size: 11px;
		font-weight: 650;
		text-transform: uppercase;
	}
	.track {
		height: 8px;
		background: var(--hb-bg-input);
		border-radius: 999px;
		overflow: hidden;
		border: 1px solid var(--hb-border-subtle);
	}
	.fill {
		height: 100%;
		min-width: 0;
		border-radius: inherit;
		transition: width 0.25s ease;
	}
	.count {
		text-align: right;
		font-variant-numeric: tabular-nums;
		color: var(--hb-text-muted);
		font-size: 12px;
	}
</style>
