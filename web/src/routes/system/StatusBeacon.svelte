<!-- The last completed health classification and check time.
     Individual check results appear below the status line. -->
<script lang="ts">
	import { healthLabel, overallHealth } from './doctor-helpers';
	import { formatDateTime } from '$lib/i18n';

	let { dbOk, meOk, checkedAt }: { dbOk: boolean; meOk: boolean; checkedAt: string } = $props();
	const tone = $derived(overallHealth(dbOk, meOk));
</script>

<div class="beacon" role="status">
	<strong class="badge" class:settled={tone === 'ok'} class:degraded={tone === 'degraded'}
		class:failed={tone === 'fail'}>{healthLabel(tone)}</strong>
	{#if checkedAt}<time datetime={checkedAt}>{formatDateTime(checkedAt)}</time>{/if}
</div>

<style>
	.beacon { display: flex; align-items: center; flex-wrap: wrap; gap: 8px 12px; }
	.degraded { background: var(--signal-soft); color: var(--signal); }
	.failed { background: var(--danger-soft); color: var(--danger); }
	time { color: var(--text-3); font: var(--t-footnote); }
</style>
