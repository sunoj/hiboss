<script lang="ts">
	import MessageRow from '$lib/components/MessageRow.svelte';
	import { sessionColor } from '$lib/design/semantics';
	import type { MessageResponse } from '$lib/api/types';
	import type { SessionGroup } from './message-helpers';
	import { sessionLabel } from '$lib/design/semantics';

	interface Props {
		group: SessionGroup;
		onSelect: (message: MessageResponse) => void;
	}

	let { group, onSelect }: Props = $props();
</script>

<section class="session-group">
	<header class="session-head">
		<span
			class="dot"
			style:background={sessionColor(group.status)}
			title={group.status}
		></span>
		<span class="session-title">{group.title}</span>
		<span class="session-meta">{group.messages.length} · {sessionLabel(group.status)}</span>
	</header>
	<div class="feed">
		{#each group.messages as message (message.id)}
			<button type="button" class="row-btn" onclick={() => onSelect(message)}>
				<MessageRow {message} />
			</button>
		{/each}
	</div>
</section>

<style>
	.session-group {
		border-bottom: 1px solid var(--hb-border);
	}
	.session-group:last-child {
		border-bottom: none;
	}
	.session-head {
		display: flex;
		align-items: center;
		gap: 0.45rem;
		padding: 0.55rem 1rem;
		background: var(--hb-bg-elevated);
		border-bottom: 1px solid var(--hb-border-subtle);
	}
	.dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		flex-shrink: 0;
	}
	.session-title {
		font-weight: 650;
		font-size: 12px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.session-meta {
		margin-left: auto;
		font-size: 11px;
		color: var(--hb-text-dim);
		text-transform: uppercase;
		letter-spacing: 0.03em;
	}
	.feed {
		display: flex;
		flex-direction: column;
	}
	.row-btn {
		display: block;
		width: 100%;
		padding: 0;
		margin: 0;
		border: none;
		background: transparent;
		text-align: left;
		cursor: pointer;
		color: inherit;
		font: inherit;
	}
	.row-btn:focus-visible {
		outline: 2px solid var(--hb-accent);
		outline-offset: -2px;
	}
</style>
