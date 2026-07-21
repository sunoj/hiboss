<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import type { AgentChannelGroup } from './groupChannels';
	import ChannelRow from './ChannelRow.svelte';

	interface Props {
		group: AgentChannelGroup;
	}

	let { group }: Props = $props();
</script>

<article class="group" aria-label={`Channels for ${group.agent_name}`}>
	<header class="head">
		<AgentIdentity name={group.agent_name} size="md" />
		<span class="count">
			{group.channels.length} channel{group.channels.length === 1 ? '' : 's'}
		</span>
	</header>
	<ul class="list">
		{#each group.channels as channel (channel.id)}
			<ChannelRow {channel} />
		{/each}
	</ul>
</article>

<style>
	.group {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
		display: flex;
		flex-direction: column;
		gap: 0.65rem;
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
		min-width: 0;
	}
	.count {
		font-size: 11px;
		color: var(--hb-text-dim);
		flex-shrink: 0;
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
	}
</style>
