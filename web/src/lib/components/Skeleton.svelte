<script lang="ts">
	import { t } from '$lib/i18n';
	interface Props {
		rows?: number;
		height?: string;
	}

	let { rows = 3, height = '1.1rem' }: Props = $props();
</script>

<div class="skel" aria-busy="true" aria-label={t('app.loading')}>
	{#each Array(rows) as _, i (i)}
		<div class="line" style:height style:width="{70 + ((i * 17) % 30)}%"></div>
	{/each}
</div>

<style>
	.skel {
		display: flex;
		flex-direction: column;
		gap: 0.55rem;
		padding: 0.5rem 0;
	}
	.line {
		border-radius: var(--hb-radius-sm);
		background: linear-gradient(
			90deg,
			var(--hb-bg-hover) 0%,
			var(--hb-border) 50%,
			var(--hb-bg-hover) 100%
		);
		background-size: 200% 100%;
		animation: shimmer 1.2s ease-in-out infinite;
	}
	@keyframes shimmer {
		0% {
			background-position: 100% 0;
		}
		100% {
			background-position: -100% 0;
		}
	}
</style>
