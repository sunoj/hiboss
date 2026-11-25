<!-- People and role controls for the admin access screen.
     Archive and rotation ask for explicit confirmation. -->
<script lang="ts">
	import type { BossRecord, BossRole } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { t } from '$lib/i18n';
	import { BOSS_ROLES, roleLabel } from './access-helpers';

	let { bosses, busy, onRotate, onRole, onArchive }: {
		bosses: BossRecord[]; busy: boolean; onRotate: (id: string) => void;
		onRole: (id: string, role: BossRole) => Promise<void>;
		onArchive: (id: string, archive: boolean) => void;
	} = $props();
	let confirm = $state<{ boss: BossRecord; kind: 'archive' | 'rotate' } | null>(null);
	const liveAdmins = $derived(bosses.filter(({ role, archived_at }) => role === 'admin' && !archived_at).length);

	async function selectRole(boss: BossRecord, input: HTMLSelectElement) {
		await onRole(boss.id, input.value as BossRole);
		const current = bosses.find(({ id }) => id === boss.id);
		input.value = current?.role ?? boss.role;
	}
</script>

<h2>{t('console.people')}</h2>
<div class="people table-region">
	<table>
		<thead><tr>
			<th scope="col">{t('form.name')}</th><th scope="col">{t('form.role')}</th>
			<th scope="col">{t('console.linkedAccounts')}</th><th scope="col">{t('form.actions')}</th>
		</tr></thead>
		<tbody>
	{#each bosses as boss (boss.id)}
		{@const last = boss.role === 'admin' && !boss.archived_at && liveAdmins === 1}
		<tr>
			<td data-label={t('form.name')}><strong>{boss.name}</strong></td>
			<td data-label={t('form.role')}>
			{#if !last && boss.archived_at === null}
				<select aria-label={t('form.role') + ' · ' + boss.name} value={boss.role} disabled={busy}
					onchange={(event) => selectRole(boss, event.currentTarget)}>
					{#each BOSS_ROLES as role}<option value={role}>{roleLabel(role)}</option>{/each}
				</select>
			{:else}<span class="badge" class:settled={boss.role === 'admin'}>{roleLabel(boss.role)}</span>{/if}
			</td>
			<td data-label={t('console.linkedAccounts')}>
				{[boss.telegram_user_id && 'Telegram', boss.discord_user_id && 'Discord']
					.filter(Boolean).join(', ') || t('devices.none')}
			</td>
			<td data-label={t('form.actions')}><div class="actions">
				{#if boss.archived_at}
					<button disabled={busy} onclick={() => onArchive(boss.id, false)}>{t('console.restore')}</button>
				{:else}
					<button disabled={busy} onclick={() => { confirm = { boss, kind: 'rotate' }; }}>
						{t('form.rotateToken')}
					</button>
					{#if !last && boss.archived_at === null && boss.id !== auth.connection?.boss?.id}
						<button disabled={busy} onclick={() => { confirm = { boss, kind: 'archive' }; }}>
							{t('console.archive')}
						</button>
					{/if}
				{/if}
				{#if last}<p>{t('console.lastAdmin')}</p>{/if}
			</div></td>
		</tr>
	{/each}
		</tbody>
	</table>
</div>

{#if confirm}
	{@const { boss, kind } = confirm}
	<ConfirmDialog message={t(kind === 'archive' ? 'console.archiveConfirm' : 'console.rotateConfirm', { name: boss.name })}
		action={t(kind === 'archive' ? 'console.archive' : 'form.rotateToken')}
		onConfirm={() => kind === 'archive' ? onArchive(boss.id, true) : onRotate(boss.id)}
		onClose={() => { confirm = null; }} />
{/if}

<style>
	h2 { font: var(--t-footnote); color: var(--text-2); padding-inline: 16px; }
	.people { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-m); }
	table { width: 100%; border-collapse: collapse; }
	th, td { padding: 12px 16px; text-align: start; border-block-end: 1px solid var(--hairline); }
	tr:last-child td { border-block-end: 0; }
	th, p { color: var(--text-3); font: var(--t-footnote); margin: 0; }
	.actions { display: flex; flex-wrap: wrap; gap: 8px; }
	select, button { min-height: var(--hit); border: 1px solid var(--field-border);
		border-radius: var(--r-s); background: var(--surface); }
</style>
