<script lang="ts">
	import type { BossCreateRequest, BossRole } from '$lib/api/types';
	import { BOSS_ROLES, roleLabel } from './access-helpers';
	import { t } from '$lib/i18n';

	interface Props {
		busy?: boolean;
		onCreate: (body: BossCreateRequest) => void;
	}

	let { busy = false, onCreate }: Props = $props();

	let name = $state('');
	let role = $state<BossRole>('viewer');
	let telegram = $state('');
	let discord = $state('');
	let open = $state(false);

	function submit(e: Event) {
		e.preventDefault();
		const trimmed = name.trim();
		if (!trimmed || busy) return;
		const body: BossCreateRequest = { name: trimmed, role };
		const tg = telegram.trim();
		const dc = discord.trim();
		if (tg) body.telegram_user_id = tg;
		if (dc) body.discord_user_id = dc;
		onCreate(body);
		name = '';
		telegram = '';
		discord = '';
		role = 'viewer';
		open = false;
	}
</script>

<div class="create">
	{#if !open}
		<button type="button" class="toggle" onclick={() => (open = true)}>{t('form.createBoss')}</button>
	{:else}
		<form class="form" onsubmit={submit}>
			<label>
				<span>{t('form.name')}</span>
				<input bind:value={name} required maxlength={80} placeholder={t('form.bossName')} disabled={busy} />
			</label>
			<label>
				<span>{t('form.role')}</span>
				<select bind:value={role} disabled={busy}>
					{#each BOSS_ROLES as r (r)}
						<option value={r}>{roleLabel(r)}</option>
					{/each}
				</select>
			</label>
			<label>
				<span>{t('form.telegramId')}</span>
				<input bind:value={telegram} placeholder={t('common.optional')} disabled={busy} />
			</label>
			<label>
				<span>{t('form.discordId')}</span>
				<input bind:value={discord} placeholder={t('common.optional')} disabled={busy} />
			</label>
			<div class="actions">
				<button type="submit" class="primary" disabled={busy || !name.trim()}>
					{busy ? t('common.creating') : t('common.create')}
				</button>
				<button type="button" class="ghost" disabled={busy} onclick={() => (open = false)}>
					{t('common.cancel')}
				</button>
			</div>
		</form>
	{/if}
</div>

<style>
	.create {
		margin-bottom: 0.75rem;
	}
	.toggle,
	.actions button {
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-panel);
		border-radius: var(--hb-radius-sm);
		padding: 0.35rem 0.7rem;
		cursor: pointer;
		color: var(--hb-text);
	}
	.toggle:hover,
	.actions button:hover:not(:disabled) {
		background: var(--hb-bg-hover);
	}
	.form {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr)) auto;
		gap: 0.55rem;
		align-items: end;
		padding: 0.75rem;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		background: var(--hb-bg-panel);
	}
	label {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
		font-size: 10px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--hb-text-muted);
	}
	input,
	select {
		font: inherit;
		font-size: 12px;
		font-weight: 500;
		text-transform: none;
		letter-spacing: normal;
		padding: 0.4rem 0.5rem;
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius-sm);
		background: var(--hb-bg-input);
		color: var(--hb-text);
	}
	.actions {
		display: flex;
		gap: 0.35rem;
	}
	.primary {
		background: color-mix(in srgb, var(--hb-accent) 22%, var(--hb-bg-elevated));
		border-color: color-mix(in srgb, var(--hb-accent) 40%, var(--hb-border));
	}
	.ghost {
		background: transparent;
		color: var(--hb-text-muted);
	}
	button:disabled {
		opacity: 0.55;
		cursor: wait;
	}
	@media (max-width: 900px) {
		.form {
			grid-template-columns: 1fr 1fr;
		}
		.actions {
			grid-column: 1 / -1;
		}
	}
</style>
