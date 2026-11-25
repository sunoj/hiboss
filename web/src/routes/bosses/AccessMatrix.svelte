<script lang="ts">
	import AgentIdentity from '$lib/components/AgentIdentity.svelte';
	import type { AgentResponse, BossRecord } from '$lib/api/types';
	import { hasAccess } from './access-helpers';
	import { t } from '$lib/i18n';

	interface Props {
		bosses: BossRecord[];
		agents: AgentResponse[];
		busyKey: string | null;
		onToggle: (bossId: string, agentId: string, next: boolean) => void;
	}

	let { bosses, agents, busyKey, onToggle }: Props = $props();

</script>

<div class="wrap" role="region" aria-label={t('page.bossesSub')}>
	<table class="matrix">
		<thead>
			<tr>
				<th scope="col" class="boss-col">{t('nav.bosses')}</th>
				{#each agents as agent (agent.id)}
					<th scope="col" class="agent-col" title={agent.id}>
						<AgentIdentity name={agent.name} size="sm" />
					</th>
				{/each}
			</tr>
		</thead>
		<tbody>
			{#each bosses as boss (boss.id)}
				<tr>
					<th scope="row" class="boss-col">
						<div class="boss-name">{boss.name}</div>
						{#if boss.role === 'admin'}<small>{t('console.adminAccess')}</small>{/if}
					</th>
					{#each agents as agent (agent.id)}
						{@const granted = boss.role === 'admin' || hasAccess(boss, agent.id)}
						<td class="cell">
							<label class="check" title={granted ? t('form.revokeAccess') : t('form.grantAccess')}>
								<input
									type="checkbox"
									checked={granted}
									disabled={busyKey !== null || boss.role === 'admin'}
									onchange={() => onToggle(boss.id, agent.id, !granted)}
								/>
								<span class="mobile-label">
									{agent.name}
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
		border: 1px solid var(--border);
		border-radius: var(--hb-radius);
		background: var(--hb-bg-panel);

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
	.agent-col {
		text-align: center;
		min-width: 5.5rem;
	}
	.boss-name {
		font-weight: 650;
		color: var(--hb-text);
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
	tbody tr:hover .boss-col,
	tbody tr:hover td {
		background: var(--hb-bg-hover);
	}
	.mobile-label { position: absolute; width: 1px; height: 1px; clip-path: inset(50%); overflow: hidden; }
	@media (max-width: 767px) {
		.matrix { min-width: 0; }
		table, tbody, tr, th, td { display: block; width: 100%; min-width: 0; }
		thead { display: none; }
		.matrix .boss-col, .matrix .cell { width: auto; min-width: 0; }
		.mobile-label { position: static; width: auto; height: auto; clip-path: none; }
		.check { display: flex; align-items: center; gap: 8px; min-height: var(--hit); }
	}
</style>
