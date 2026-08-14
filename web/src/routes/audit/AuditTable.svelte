<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import { formatRelativeTime } from '$lib/api/mappers';
	import type { AuditActorType, AuditEntry } from '$lib/api/types';
	import {
		actorTypeLabel,
		formatResource,
		truncateDetails
	} from './audit-helpers';
	import { t } from '$lib/i18n';

	interface Props {
		entries: AuditEntry[];
	}

	let { entries }: Props = $props();

	function actorTone(type: AuditActorType): string {
		switch (type) {
			case 'boss':
				return 'var(--hb-dir-boss-to-agent)';
			case 'agent':
				return 'var(--hb-dir-agent-to-boss)';
			case 'system':
				return 'var(--hb-text-muted)';
		}
	}
</script>

<div class="wrap" role="region" aria-label={t('form.auditLog')}>
	<table class="table">
		<thead>
			<tr>
				<th scope="col">{t('form.when')}</th>
				<th scope="col">{t('form.actor')}</th>
				<th scope="col">{t('form.action')}</th>
				<th scope="col">{t('form.resource')}</th>
				<th scope="col">{t('form.details')}</th>
			</tr>
		</thead>
		<tbody>
			{#each entries as row (row.id)}
				<tr>
					<td class="when" title={row.created_at}>
						{formatRelativeTime(row.created_at)}
					</td>
					<td class="actor">
						<span
							class="type"
							style:color={actorTone(row.actor_type)}
							title={actorTypeLabel(row.actor_type)}
						>
							{actorTypeLabel(row.actor_type)}
						</span>
						<AgentIdentity name={row.actor_id} size="sm" />
					</td>
					<td class="action">
						<code>{row.action}</code>
					</td>
					<td class="resource" title={row.resource_id ?? undefined}>
						{formatResource(row.resource_type, row.resource_id)}
					</td>
					<td class="details" title={row.details ?? undefined}>
						{truncateDetails(row.details)}
					</td>
				</tr>
			{/each}
		</tbody>
	</table>
</div>

<style>
	.wrap {
		overflow-x: auto;
	}
	.table {
		width: 100%;
		border-collapse: collapse;
		font-size: 12px;
	}
	th,
	td {
		padding: 0.55rem 0.85rem;
		text-align: left;
		border-bottom: 1px solid var(--hb-border-subtle);
		vertical-align: middle;
	}
	th {
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
		background: var(--hb-bg-elevated);
		position: sticky;
		top: 0;
		z-index: 1;
	}
	tr:hover td {
		background: var(--hb-bg-hover);
	}
	.when {
		white-space: nowrap;
		color: var(--hb-text-muted);
		font-family: var(--hb-font-mono);
		font-size: 11px;
	}
	.actor {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
		min-width: 8rem;
	}
	.type {
		font-size: 9px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.action code {
		font-family: var(--hb-font-mono);
		font-size: 11px;
		color: var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 12%, transparent);
		padding: 0.1rem 0.35rem;
		border-radius: var(--hb-radius-sm);
	}
	.resource {
		font-family: var(--hb-font-mono);
		font-size: 11px;
		color: var(--hb-text-muted);
		white-space: nowrap;
	}
	.details {
		color: var(--hb-text-dim);
		max-width: 22rem;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
</style>
