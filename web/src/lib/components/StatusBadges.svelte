<script lang="ts">
	import {
		directionColor,
		directionLabel,
		priorityBg,
		priorityColor,
		statusColor,
		type Direction,
		type MessageStatus,
		type Priority
	} from '$lib/design/semantics';

	interface Props {
		priority?: Priority;
		status?: MessageStatus;
		direction?: Direction;
		compact?: boolean;
	}

	let { priority, status, direction, compact = false }: Props = $props();
</script>

<span class="badges" class:compact>
	{#if priority}
		<span
			class="badge priority"
			style:color={priorityColor(priority)}
			style:background={priorityBg(priority)}
		>
			{priority}
		</span>
	{/if}
	{#if direction}
		<span class="badge direction" style:color={directionColor(direction)}>
			{directionLabel(direction)}
		</span>
	{/if}
	{#if status}
		<span class="badge status" style:color={statusColor(status)}>
			<span class="dot" style:background={statusColor(status)}></span>
			{status}
		</span>
	{/if}
</span>

<style>
	.badges {
		display: inline-flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		align-items: center;
	}
	.badge {
		display: inline-flex;
		align-items: center;
		gap: 0.3rem;
		padding: 0.1rem 0.4rem;
		border-radius: var(--hb-radius-sm);
		font-size: 10px;
		font-weight: 600;
		letter-spacing: 0.02em;
		text-transform: uppercase;
		border: 1px solid var(--hb-border-subtle);
		line-height: 1.3;
	}
	.badge.priority {
		border-color: transparent;
	}
	.badge.direction,
	.badge.status {
		background: transparent;
	}
	.dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
	}
	.compact .badge {
		padding: 0.05rem 0.3rem;
		font-size: 9px;
	}
</style>
