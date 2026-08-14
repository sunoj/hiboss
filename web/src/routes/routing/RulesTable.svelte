<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import type { RoutingRuleResponse } from '$lib/api/types';
	import {
		isRuleEnabled,
		resolveAgentName,
		type RuleSortKey,
		type SortDir
	} from './sortRules';
	import { t } from '$lib/i18n';

	interface Props {
		rules: RoutingRuleResponse[];
		agentNames: Map<string, string>;
		sortKey: RuleSortKey;
		sortDir: SortDir;
		busyId?: string | null;
		onSort: (key: RuleSortKey) => void;
		onDelete: (id: string) => void;
	}

	let {
		rules,
		agentNames,
		sortKey,
		sortDir,
		busyId = null,
		onSort,
		onDelete
	}: Props = $props();

	const columns: { key: RuleSortKey; label: string }[] = [
		{ key: 'channel', label: t('form.channel') },
		{ key: 'pattern', label: t('form.pattern') },
		{ key: 'target', label: t('form.targetAgent') },
		{ key: 'priority', label: t('form.priority') },
		{ key: 'enabled', label: t('form.enabledReadOnly') }
	];

	function ariaSort(key: RuleSortKey): 'ascending' | 'descending' | 'none' {
		if (sortKey !== key) return 'none';
		return sortDir === 'asc' ? 'ascending' : 'descending';
	}

	function marker(key: RuleSortKey): string {
		if (sortKey !== key) return '';
		return sortDir === 'asc' ? ' ↑' : ' ↓';
	}
</script>

<div class="wrap">
	<div class="table-scroll">
		<table>
			<thead>
				<tr>
					{#each columns as col (col.key)}
						<th aria-sort={ariaSort(col.key)}>
							<button type="button" class="sort" onclick={() => onSort(col.key)}>
								{col.label}{marker(col.key)}
							</button>
						</th>
					{/each}
					<th class="actions">{t('form.actions')}</th>
				</tr>
			</thead>
			<tbody>
				{#each rules as row (row.id)}
					<tr>
						<td>
							<span class="channel">{row.channel}</span>
						</td>
						<td>
							<code class="pattern">{row.pattern}</code>
						</td>
						<td>
							<AgentIdentity
								name={resolveAgentName(agentNames, row.target_agent_id) ??
									row.target_agent_id}
							/>
						</td>
						<td class="num">{row.priority}</td>
						<td>
							<label class="toggle" title={t('form.enabledReadOnly')}>
								<input
									type="checkbox"
									checked={isRuleEnabled(row.enabled)}
									disabled
									aria-label={t('form.enabledReadOnlyAria')}
								/>
								<span class="toggle-label">
									{isRuleEnabled(row.enabled) ? t('channel.on') : t('channel.off')}
								</span>
							</label>
						</td>
						<td class="actions">
							<button
								type="button"
								class="danger"
								disabled={busyId === row.id}
								onclick={() => onDelete(row.id)}
							>
								{busyId === row.id ? t('common.deleting') : t('common.delete')}
							</button>
						</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
</div>

<style>
	.wrap {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		box-shadow: var(--hb-shadow);
		overflow: hidden;
	}
	.danger,
	.sort {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.3rem 0.65rem;
		cursor: pointer;
		color: var(--hb-text);
		font: inherit;
	}
	.danger:disabled {
		opacity: 0.45;
		cursor: wait;
	}
	.danger {
		color: var(--hb-danger);
		border-color: color-mix(in srgb, var(--hb-danger) 35%, var(--hb-border));
	}
	.table-scroll {
		overflow-x: auto;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 13px;
	}
	th,
	td {
		text-align: left;
		padding: 0.55rem 0.85rem;
		border-bottom: 1px solid var(--hb-border-subtle);
		vertical-align: middle;
	}
	th {
		font-size: 11px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--hb-text-muted);
		font-weight: 700;
		white-space: nowrap;
	}
	.sort {
		border: none;
		background: transparent;
		padding: 0;
		color: inherit;
		font: inherit;
		font-weight: 700;
		letter-spacing: 0.04em;
		text-transform: uppercase;
		cursor: pointer;
	}
	.sort:hover {
		color: var(--hb-text);
	}
	tbody tr:hover {
		background: var(--hb-bg-hover);
	}
	.channel {
		font-family: var(--hb-font-mono);
		font-size: 12px;
		text-transform: lowercase;
		padding: 0.1rem 0.4rem;
		border-radius: var(--hb-radius-sm);
		border: 1px solid var(--hb-border-subtle);
		background: var(--hb-bg-input);
		color: var(--hb-accent);
	}
	.pattern {
		font-family: var(--hb-font-mono);
		font-size: 12px;
		color: var(--hb-text);
		word-break: break-all;
	}
	.num {
		font-family: var(--hb-font-mono);
		font-variant-numeric: tabular-nums;
	}
	.toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		cursor: not-allowed;
		color: var(--hb-text-muted);
		font-size: 12px;
	}
	.toggle input {
		accent-color: var(--hb-success);
	}
	.toggle-label {
		text-transform: uppercase;
		letter-spacing: 0.03em;
		font-size: 10px;
		font-weight: 650;
	}
	.actions {
		width: 1%;
		white-space: nowrap;
	}
</style>
