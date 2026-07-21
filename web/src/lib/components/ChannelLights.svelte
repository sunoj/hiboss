<script lang="ts">
	import type { ChannelHealth } from '$lib/api/types';

	interface Props {
		channels: ChannelHealth[];
	}

	let { channels }: Props = $props();
</script>

<ul class="channels">
	{#each channels as ch (ch.channel)}
		<li class:ok={ch.configured} class:off={!ch.configured}>
			<span class="light" aria-hidden="true"></span>
			<span class="name">{ch.channel}</span>
			<span class="state">{ch.configured ? 'configured' : 'missing'}</span>
		</li>
	{/each}
</ul>

<style>
	.channels {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
	}
	li {
		display: grid;
		grid-template-columns: 12px 1fr auto;
		gap: 0.55rem;
		align-items: center;
		padding: 0.35rem 0.45rem;
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-input);
		border: 1px solid var(--hb-border-subtle);
	}
	.light {
		width: 8px;
		height: 8px;
		border-radius: 50%;
	}
	.ok .light {
		background: var(--hb-success);
		box-shadow: 0 0 0 2px color-mix(in srgb, var(--hb-success) 25%, transparent);
	}
	.off .light {
		background: var(--hb-text-dim);
	}
	.name {
		text-transform: lowercase;
		font-family: var(--hb-font-mono);
		font-size: 12px;
	}
	.state {
		font-size: 11px;
		color: var(--hb-text-dim);
	}
	.ok .state {
		color: var(--hb-success);
	}
</style>
