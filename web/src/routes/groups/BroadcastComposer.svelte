<script lang="ts">
	import StatusBadges from '$lib/components/StatusBadges.svelte';
	import type { BroadcastGroupRequest, GroupResponse } from '$lib/api/types';
	import { PRIORITIES, type Priority } from '$lib/design/semantics';
	import { canSendBroadcast } from './groupHelpers';

	interface Props {
		groups: GroupResponse[];
		busy?: boolean;
		onBroadcast: (groupId: string, body: BroadcastGroupRequest) => void;
	}

	let { groups, busy = false, onBroadcast }: Props = $props();

	let selectedId = $state('');
	let body = $state('');
	let priority = $state<Priority>('normal');

	const selected = $derived(groups.find((g) => g.id === selectedId) ?? null);
	const ready = $derived(canSendBroadcast(selectedId, body));

	function submit(e: Event) {
		e.preventDefault();
		if (!ready || busy) return;
		const payload: BroadcastGroupRequest = { body: body.trim() };
		if (priority !== 'normal') payload.priority = priority;
		onBroadcast(selectedId, payload);
		body = '';
	}
</script>

<section class="composer" aria-label="Group broadcast composer">
	<header class="head">
		<h2>Broadcast</h2>
		<p class="sub">整组广播 — message every member of a group</p>
	</header>

	<form class="form" onsubmit={submit}>
		<label class="field">
			<span>Group</span>
			<select bind:value={selectedId} disabled={busy || groups.length === 0}>
				<option value="">Select a group…</option>
				{#each groups as group (group.id)}
					<option value={group.id}>{group.name}</option>
				{/each}
			</select>
		</label>

		<label class="field">
			<span>Priority</span>
			<div class="prio-row">
				<select bind:value={priority} disabled={busy}>
					{#each PRIORITIES as p (p)}
						<option value={p}>{p}</option>
					{/each}
				</select>
				<StatusBadges {priority} compact />
			</div>
		</label>

		<label class="field">
			<span>Message</span>
			<textarea
				rows="4"
				placeholder={selected ? `Broadcast to ${selected.name}…` : 'Write a group broadcast…'}
				bind:value={body}
				disabled={busy}
			></textarea>
		</label>

		<div class="footer">
			<button type="submit" class="send" disabled={busy || !ready}>
				{busy ? 'Sending…' : 'Send broadcast'}
			</button>
		</div>
	</form>
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
	.form {
		display: flex;
		flex-direction: column;
		gap: 0.65rem;
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
	.prio-row {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}
	.prio-row select {
		flex: 1;
		min-width: 0;
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
	}
	select:disabled,
	textarea:disabled {
		opacity: 0.6;
		cursor: wait;
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
		cursor: pointer;
	}
	.send:hover:not(:disabled) {
		background: color-mix(in srgb, var(--hb-accent) 32%, var(--hb-bg-elevated));
	}
	.send:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}
</style>
