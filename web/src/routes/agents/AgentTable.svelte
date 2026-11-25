<!-- Lists agents and their canonical project slugs.
     Depends on boss agent responses and shared console formatting. -->
<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AgentResponse } from '$lib/api/types';
	import { lastUsedLabel, roleLabel } from './agent-helpers';
	import { t } from '$lib/i18n';

	interface Props {
		agents: AgentResponse[];
		selectedId: string | null;
	}

	let { agents, selectedId }: Props = $props();
</script>

<ul class="rows">
	{#each agents as agent (agent.id)}
		<li>
			<a href={'/agents/' + encodeURIComponent(agent.id)} aria-current={selectedId === agent.id ? 'page' : undefined}>
				<AgentIdentity name={agent.name} size="row" showName={false} />
				<span class="text">
					<strong title={agent.name}>{agent.name}</strong>
					<span title={agent.project_slugs?.join(', ')}>
						{[roleLabel(agent.role), ...agent.project_slugs ?? []].join(' · ')}
					</span>
					{#if agent.kind === 'integration'}<span class="badge live">{t('console.integration')}</span>{/if}
					{#if agent.admin}<span class="badge settled">{t('console.adminCapability')}</span>{/if}
				</span>
				{#if agent.last_used_at}
					<time datetime={agent.last_used_at} title={t('form.lastSeen')}>
						{formatRelativeTime(agent.last_used_at)}
					</time>
				{:else}
					<span class="when">{lastUsedLabel(agent.last_used_at)}</span>
				{/if}
			</a>
		</li>
	{/each}
</ul>

<style>
	.rows { list-style: none; padding: 0; margin: 0; }
	li + li { border-block-start: 1px solid var(--hairline); }
	a { display: flex; align-items: center; gap: 12px; padding: 12px 16px; min-height: 56px; }
	a:hover { background: var(--surface-2); }
	a:focus-visible { outline-offset: -2px; }
	a[aria-current="page"] { background: var(--live-soft); }
	.text { flex: 1; min-width: 0; }
	.text > :not(.badge) { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	strong { font: var(--t-callout); font-weight: 600; }
	time, .when, .text > span:not(.badge) { font: var(--t-footnote); color: var(--text-3); }
	.badge { margin-inline-end: 4px; }
</style>
