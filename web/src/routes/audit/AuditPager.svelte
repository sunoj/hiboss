<script lang="ts">
	import {
		canGoNext,
		canGoPrev,
		formatPageLabel,
		nextOffset,
		prevOffset
	} from './audit-helpers';

	interface Props {
		offset: number;
		limit: number;
		total: number;
		visibleCount: number;
		disabled?: boolean;
		onPage: (offset: number) => void;
	}

	let {
		offset,
		limit,
		total,
		visibleCount,
		disabled = false,
		onPage
	}: Props = $props();

	const label = $derived(formatPageLabel(offset, limit, total, visibleCount));
	const prevEnabled = $derived(!disabled && canGoPrev(offset));
	const nextEnabled = $derived(!disabled && canGoNext(offset, limit, total));
</script>

<nav class="pager" aria-label="Audit log pagination">
	<span class="range">{label}</span>
	<div class="btns">
		<button
			type="button"
			disabled={!prevEnabled}
			onclick={() => onPage(prevOffset(offset, limit))}
		>
			Previous
		</button>
		<button
			type="button"
			disabled={!nextEnabled}
			onclick={() => onPage(nextOffset(offset, limit))}
		>
			Next
		</button>
	</div>
</nav>

<style>
	.pager {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: center;
		gap: 0.65rem;
		padding: 0.65rem 1rem;
		border-top: 1px solid var(--hb-border-subtle);
	}
	.range {
		color: var(--hb-text-dim);
		font-size: 11px;
		font-family: var(--hb-font-mono);
	}
	.btns {
		display: flex;
		gap: 0.4rem;
	}
	button {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		color: var(--hb-text);
		border-radius: var(--hb-radius-sm);
		padding: 0.3rem 0.7rem;
		font-weight: 600;
		font-size: 12px;
		cursor: pointer;
	}
	button:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	button:disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}
</style>
