<!-- People and role controls for the admin access screen.
     Archive and rotation ask for explicit confirmation. -->
<script lang="ts">
	import type { BossRecord, BossRole } from '$lib/api/types';
	import { auth } from '$lib/stores/auth.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { t } from '$lib/i18n';
	import { bindingSummary, BOSS_ROLES, roleLabel } from './access-helpers';

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
<div class="people">
	{#each bosses as boss (boss.id)}
		{@const bindings = bindingSummary(boss)}
		{@const last = boss.role === 'admin' && !boss.archived_at && liveAdmins === 1}
		<article aria-label={boss.name}>
			<strong>{boss.name}</strong>
			{#if !last && boss.archived_at === null}
				<select aria-label={t('form.role') + ' · ' + boss.name} value={boss.role} disabled={busy}
					onchange={(event) => selectRole(boss, event.currentTarget)}>
					{#each BOSS_ROLES as role}<option value={role}>{roleLabel(role)}</option>{/each}
				</select>
			{:else}<span>{roleLabel(boss.role)}</span>{/if}
			<div>Telegram {bindings.telegram} · Discord {bindings.discord}</div>
			<div class="actions">
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
			</div>
			{#if last}<p>{t('console.lastAdmin')}</p>{/if}
		</article>
	{/each}
</div>

{#if confirm}
	{@const { boss, kind } = confirm}
	<ConfirmDialog message={t(kind === 'archive' ? 'console.archiveConfirm' : 'console.rotateConfirm', { name: boss.name })}
		action={t(kind === 'archive' ? 'console.archive' : 'form.rotateToken')}
		onConfirm={() => kind === 'archive' ? onArchive(boss.id, true) : onRotate(boss.id)}
		onClose={() => { confirm = null; }} />
{/if}

<style>
	h2 { font: var(--t-title); }
	.people { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-m); }
	article { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; padding: 12px; overflow-wrap: anywhere; }
	article + article { border-block-start: 1px solid var(--hairline); }
	article p { flex-basis: 100%; color: var(--text-3); margin: 0; }
	.actions { display: flex; flex-wrap: wrap; gap: 8px; }
	select, button { min-height: var(--hit); border: 1px solid var(--field-border);
		border-radius: var(--r-s); background: var(--surface); }
</style>
