<!-- The visible deadline on an open decision card or detail.
     The machine-readable timestamp remains available on the time element. -->
<script lang="ts">
	import { getLocale, t } from '$lib/i18n';
	import { inputs } from './inputs.svelte';
	import { remainingTime } from './timing';

	let { deadline }: { deadline: string | null } = $props();
	const due = $derived(deadline && Number.isFinite(Date.parse(deadline)) ? new Intl.DateTimeFormat(getLocale(), {
		dateStyle: 'medium', timeStyle: 'short'
	}).format(Date.parse(deadline)) : '');
	const seconds = $derived(deadline ? Math.ceil((Date.parse(deadline) - inputs.now) / 1000) : 0);
</script>

{#if deadline && seconds > 0}
	<time datetime={deadline} title={due}>
		{t('console.timeLeft', { time: remainingTime(seconds, getLocale()) })}
	</time>
{:else if !deadline}
	<span>{t('console.noDeadline')}</span>
{/if}

<style>
	time { color: var(--signal); }
</style>
