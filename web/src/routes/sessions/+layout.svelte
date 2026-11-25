<!-- Searchable session directory with an addressable transcript pane.
     Required inputs take precedence over live activity. -->
<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import '$lib/design/console-split.css';
	import { LoadState } from '$lib/stores/load-state.svelte';
	import { inputs } from '$lib/decisions/inputs.svelte';
	import { deadlineOf } from '$lib/decisions/decision';
	import { formatDateTime, t } from '$lib/i18n';
	import type { SessionResponse } from '$lib/api/types';
	import ErrorState from '$lib/components/ErrorState.svelte';
	import EmptyState from '$lib/components/EmptyState.svelte';
	import Skeleton from '$lib/components/Skeleton.svelte';

	let { children } = $props();
	let search = $state('');
	let field: HTMLInputElement;
	let sessions = $state<SessionResponse[]>([]);
	const loadState = new LoadState();
	const needs = $derived(new Set(inputs.messages.filter((message) => !inputs.settled.has(message.id)
		&& !(Date.parse(deadlineOf(message) ?? '') <= inputs.now)).map(({ session_id }) => session_id)));
	const visible = $derived(sessions.filter((session) => {
		const project = page.url.searchParams.get('project');
		if (project && project !== session.project_slug) return false;
		return [session.label, session.project_slug, session.branch, session.agent_name]
			.some((value) => value?.toLowerCase().includes(search.trim().toLowerCase())) || !search.trim();
	}));
	const groups = $derived([
		{ label: 'console.needs', rows: visible.filter(({ id }) => needs.has(id)) },
		{ label: 'console.workingNow', rows: visible.filter(({ id, status }) => !needs.has(id) && status === 'working') },
		{ label: 'session.idle', rows: visible.filter(({ id, status }) => !needs.has(id)
			&& !['working', 'completed'].includes(status)) },
		{ label: 'session.completed', rows: visible.filter(({ id, status }) => !needs.has(id) && status === 'completed') }
	] as const);

	async function load() {
		await loadState.run(async (client) => { sessions = (await client.sessions()).sessions; });
	}

	function shortcut(event: KeyboardEvent) {
		if (event.key !== '/' || event.ctrlKey || event.metaKey || !field?.offsetWidth
			|| (event.target instanceof Element && event.target.closest('input, textarea, select, [contenteditable]'))) {
			return;
		}
		event.preventDefault();
		field.focus();
	}

	onMount(() => { void load(); });
</script>

<svelte:window onkeydown={shortcut} />

{#snippet rows(items: SessionResponse[])}
	<div class="rows">
		{#each items as session (session.id)}
			<a href={'/sessions/' + encodeURIComponent(session.id)}
				aria-current={page.params.id === session.id ? 'page' : undefined}>
				<strong>{[session.project_slug ?? session.label ?? session.id, session.branch]
					.filter(Boolean).join(' · ')}</strong>
				<span>{[session.agent_name, session.status_text].filter(Boolean).join(' · ')}</span>
				<time datetime={session.last_seen_at} title={formatDateTime(session.last_seen_at)}>
					{formatDateTime(session.last_seen_at)}
				</time>
			</a>
		{/each}
	</div>
{/snippet}

<div class="console-split" data-detail={page.params.id ? '' : undefined}>
	<section class="console-list">
		<h1>{t('page.sessions')}</h1>
		<label>{t('console.sessionSearch')}<input type="search" bind:this={field} bind:value={search} /></label>
		{#if loadState.error}
			<ErrorState message={loadState.error} onRetry={load} />
		{:else if loadState.loading}
			<Skeleton rows={4} />
		{:else if !visible.length}
			<EmptyState title={t('page.noSessions')} detail={t('page.noSessionsDetail')} />
		{:else}
			{#each groups as group (group.label)}
				{#if group.label === 'session.completed'}
					<details><summary>{t(group.label)} · {group.rows.length}</summary>{@render rows(group.rows)}</details>
				{:else}
					<h2>{t(group.label)} · {group.rows.length}</h2>
					{@render rows(group.rows)}
				{/if}
			{/each}
		{/if}
	</section>
	{@render children()}
</div>

<style>
	h1 { font: var(--t-large); margin: 0 0 16px; }
	h2, summary { font: var(--t-headline); text-transform: capitalize; margin: 16px 0 8px; }
	label { display: grid; gap: 4px; }
	input { min-height: var(--hit); border: 1px solid var(--field-border); border-radius: 8px; padding-inline: 12px; }
	.rows { background: var(--surface); border-radius: var(--r-m); }
	a { display: grid; gap: 2px; padding: 10px 12px; border-bottom: 1px solid var(--hairline); overflow-wrap: anywhere; }
	a[aria-current="page"] { background: var(--live-soft); }
	span, time { color: var(--text-3); font: var(--t-caption); }
	summary { cursor: pointer; min-height: var(--hit); }
</style>
