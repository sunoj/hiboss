<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import type { AgentResponse, BossRecord } from '$lib/api/types';
	import { bindingSummary, hasAccess, shortId } from './access-helpers';
	import RoleBadge from './RoleBadge.svelte';
	import { t } from '$lib/i18n';

	interface Props {
		bosses: BossRecord[];
		agents: AgentResponse[];
		busyKey: string | null;
		onToggle: (bossId: string, agentId: string, next: boolean) => void;
		onRotate: (bossId: string) => void;
	}

	let { bosses, agents, busyKey, onToggle, onRotate }: Props = $props();

	function cellKey(bossId: string, agentId: string): string {
		return `${bossId}:${agentId}`;
	}
</script>

<div class="wrap" role="region" aria-label={t('page.bossesSub')}>
	<table class="matrix">
		<thead>
			<tr>
				<th class="boss-col">{t('nav.bosses')}</th>
				<th class="meta">{t('form.role')}</th>
				<th class="meta">{t('form.channel')}</th>
				<th class="meta">{t('connect.bossToken')}</th>
				{#each agents as agent (agent.id)}
					<th class="agent-col" title={agent.id}>
						<AgentIdentity name={agent.name} size="sm" />
					</th>
				{/each}
			</tr>
		</thead>
		<tbody>
			{#each bosses as boss (boss.id)}
				{@const bind = bindingSummary(boss)}
				<tr>
					<td class="boss-col">
						<div class="boss-name">{boss.name}</div>
						<code class="id" title={boss.id}>{shortId(boss.id)}</code>
					</td>
					<td class="meta"><RoleBadge role={boss.role} /></td>
					<td class="meta bindings">
						<div><span class="k">TG</span> {bind.telegram}</div>
						<div><span class="k">DC</span> {bind.discord}</div>
					</td>
					<td class="meta">
						<button
							type="button"
							class="rotate"
							disabled={busyKey === `rotate:${boss.id}`}
							onclick={() => onRotate(boss.id)}
						>
							{t('form.rotateToken')}
						</button>
					</td>
					{#each agents as agent (agent.id)}
						{@const granted = hasAccess(boss, agent.id)}
						{@const key = cellKey(boss.id, agent.id)}
						<td class="cell">
							<label class="check" title={granted ? t('form.revokeAccess') : t('form.grantAccess')}>
								<input
									type="checkbox"
									checked={granted}
									disabled={busyKey === key}
									onchange={() => onToggle(boss.id, agent.id, !granted)}
								/>
								<span class="visually-hidden">
									{boss.name} ↔ {agent.name}
								</span>
							</label>
						</td>
					{/each}
				</tr>
			{/each}
		</tbody>
	</table>
</div>

<style>
	.wrap {
		overflow: auto;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		background: var(--hb-bg-panel);
		box-shadow: var(--hb-shadow);
	}
	.matrix {
		width: 100%;
		border-collapse: collapse;
		font-size: 12px;
		min-width: 640px;
	}
	th,
	td {
		padding: 0.55rem 0.65rem;
		border-bottom: 1px solid var(--hb-border-subtle);
		vertical-align: middle;
		text-align: left;
	}
	th {
		position: sticky;
		top: 0;
		z-index: 1;
		background: var(--hb-bg-elevated);
		color: var(--hb-text-muted);
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		white-space: nowrap;
	}
	.boss-col {
		position: sticky;
		left: 0;
		z-index: 2;
		background: var(--hb-bg-panel);
		min-width: 8rem;
	}
	th.boss-col {
		z-index: 3;
		background: var(--hb-bg-elevated);
	}
	.meta {
		white-space: nowrap;
		color: var(--hb-text-muted);
	}
	.agent-col {
		text-align: center;
		min-width: 5.5rem;
	}
	.boss-name {
		font-weight: 650;
		color: var(--hb-text);
	}
	.id {
		font-family: var(--hb-font-mono);
		font-size: 10px;
		color: var(--hb-text-dim);
	}
	.bindings {
		font-family: var(--hb-font-mono);
		font-size: 11px;
		line-height: 1.45;
	}
	.k {
		display: inline-block;
		min-width: 1.4rem;
		color: var(--hb-text-dim);
		font-weight: 700;
		font-size: 9px;
	}
	.cell {
		text-align: center;
	}
	.check {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		cursor: pointer;
		padding: 0.25rem;
	}
	.check input {
		width: 1rem;
		height: 1rem;
		accent-color: var(--hb-accent);
		cursor: pointer;
	}
	.check input:disabled {
		cursor: wait;
		opacity: 0.55;
	}
	.rotate {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-elevated);
		border-radius: var(--hb-radius-sm);
		padding: 0.25rem 0.55rem;
		font-size: 11px;
		cursor: pointer;
		color: var(--hb-text);
	}
	.rotate:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.rotate:disabled {
		opacity: 0.55;
		cursor: wait;
	}
	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		margin: -1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		border: 0;
	}
	tbody tr:hover .boss-col,
	tbody tr:hover td {
		background: var(--hb-bg-hover);
	}
</style>
