<script lang="ts">
	import { agentColor, agentInitials } from '$lib/design/agent-color';
	import { t } from '$lib/i18n';

	interface Props {
		name: string | null | undefined;
		size?: 'sm' | 'md';
		showName?: boolean;
	}

	let { name, size = 'sm', showName = true }: Props = $props();

	const color = $derived(agentColor(name));
	const initials = $derived(agentInitials(name));
	const label = $derived(name?.trim() || t('common.unknown'));
</script>

<span class="agent" class:sm={size === 'sm'} class:md={size === 'md'} title={label}>
	<span class="dot" style:background={color} aria-hidden="true">{initials}</span>
	{#if showName}
		<span class="name">{label}</span>
	{/if}
</span>

<style>
	.agent {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		min-width: 0;
	}
	.dot {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border-radius: 50%;
		color: #0c0e12;
		font-weight: 700;
		font-family: var(--hb-font-mono);
		flex-shrink: 0;
	}
	.sm .dot {
		width: 18px;
		height: 18px;
		font-size: 9px;
	}
	.md .dot {
		width: 22px;
		height: 22px;
		font-size: 10px;
	}
	.name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 550;
	}
</style>
