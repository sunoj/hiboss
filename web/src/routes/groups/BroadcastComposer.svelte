<script lang="ts">
	import type { GroupResponse } from '$lib/api/types';
	import { WRITE_DISABLED_NOTE } from './groupHelpers';

	interface Props {
		groups: GroupResponse[];
	}

	let { groups }: Props = $props();

	let selectedId = $state('');
	let body = $state('');
	let priority = $state<'normal' | 'high' | 'critical' | 'low'>('normal');

	const selected = $derived(groups.find((g) => g.id === selectedId) ?? null);
</script>

<section class="composer" aria-label="Group broadcast composer">
	<header class="head">
		<h2>Broadcast</h2>
		<p class="sub">整组广播 — message every member of a group</p>
	</header>

	<label class="field">
		<span>Group</span>
		<select bind:value={selectedId} disabled>
			<option value="">Select a group…</option>
			{#each groups as group (group.id)}
				<option value={group.id}>{group.name}</option>
			{/each}
		</select>
	</label>

	<label class="field">
		<span>Priority</span>
		<select bind:value={priority} disabled>
			<option value="low">low</option>
			<option value="normal">normal</option>
			<option value="high">high</option>
			<option value="critical">critical</option>
		</select>
	</label>

	<label class="field">
		<span>Message</span>
		<textarea
			rows="4"
			placeholder={selected ? `Broadcast to ${selected.name}…` : 'Write a group broadcast…'}
			bind:value={body}
			disabled
		></textarea>
	</label>

	<div class="footer">
		<button type="button" class="send" disabled title={WRITE_DISABLED_NOTE}>Send broadcast</button>
		<p class="note" role="note">{WRITE_DISABLED_NOTE}</p>
	</div>
</section>

<style>
	.composer {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		box-shadow: var(--hb-shadow);
		display: flex;
		flex-direction: column;
		gap: 0.65rem;
	}
	.head h2 {
		margin: 0;
		font-size: 12px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--hb-text-muted);
	}
	.sub {
		margin: 0.15rem 0 0;
		font-size: 11px;
		color: var(--hb-text-dim);
	}
	.field {
		display: flex;
		flex-direction: column;
		gap: 0.3rem;
		font-size: 11px;
		font-weight: 650;
		color: var(--hb-text-muted);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	select,
	textarea {
		width: 100%;
		box-sizing: border-box;
		border: 1px solid var(--hb-border);
		background: var(--hb-bg-input);
		color: var(--hb-text);
		border-radius: var(--hb-radius-sm);
		padding: 0.45rem 0.55rem;
		font: inherit;
		font-size: 12px;
		text-transform: none;
		letter-spacing: normal;
		font-weight: 400;
		resize: vertical;
		opacity: 0.55;
		cursor: not-allowed;
	}
	.footer {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 0.35rem;
	}
	.send {
		border: 1px solid var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 22%, var(--hb-bg-elevated));
		border-radius: var(--hb-radius-sm);
		padding: 0.4rem 0.75rem;
		font: inherit;
		font-size: 12px;
		font-weight: 600;
		color: var(--hb-text);
		opacity: 0.55;
		cursor: not-allowed;
	}
	.note {
		margin: 0;
		font-size: 10px;
		color: var(--hb-warning);
		text-transform: none;
		letter-spacing: normal;
		font-weight: 400;
	}
</style>
