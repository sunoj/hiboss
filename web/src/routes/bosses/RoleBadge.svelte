<script lang="ts">
	import type { BossRole } from '$lib/api/types';
	import { roleLabel, roleTone } from './access-helpers';

	interface Props {
		role: BossRole | string;
	}

	let { role }: Props = $props();
	const tone = $derived(roleTone(role));
</script>

<span class="badge" class:admin={tone === 'admin'} class:manager={tone === 'manager'} class:viewer={tone === 'viewer'}>
	{roleLabel(role)}
</span>

<style>
	.badge {
		display: inline-flex;
		align-items: center;
		padding: 0.1rem 0.4rem;
		border-radius: var(--hb-radius-sm);
		font-size: 10px;
		font-weight: 650;
		letter-spacing: 0.03em;
		text-transform: uppercase;
		border: 1px solid var(--hb-border-subtle);
		color: var(--hb-text-muted);
		background: color-mix(in srgb, var(--hb-text-dim) 12%, transparent);
	}
	.badge.admin {
		color: var(--hb-danger);
		background: color-mix(in srgb, var(--hb-danger) 14%, transparent);
		border-color: transparent;
	}
	.badge.manager {
		color: var(--hb-accent);
		background: color-mix(in srgb, var(--hb-accent) 14%, transparent);
		border-color: transparent;
	}
	.badge.viewer {
		color: var(--hb-text-muted);
		background: color-mix(in srgb, var(--hb-text-dim) 14%, transparent);
	}
</style>
