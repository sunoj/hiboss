<script lang="ts">
	interface Props {
		label: string;
		value: string | number;
		hint?: string;
		tone?: 'default' | 'warn' | 'danger' | 'accent';
	}

	let { label, value, hint, tone = 'default' }: Props = $props();
</script>

<div class="kpi" class:warn={tone === 'warn'} class:danger={tone === 'danger'} class:accent={tone === 'accent'}>
	<div class="label">{label}</div>
	<div class="value">{value}</div>
	{#if hint}
		<div class="hint">{hint}</div>
	{/if}
</div>

<style>
	.kpi {
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 0.85rem 1rem;
		min-height: 84px;
		box-shadow: var(--hb-shadow);
	}
	.warn {
		border-color: color-mix(in srgb, var(--hb-warning) 45%, var(--hb-border));
	}
	.danger {
		border-color: color-mix(in srgb, var(--hb-danger) 45%, var(--hb-border));
	}
	.accent {
		border-color: color-mix(in srgb, var(--hb-accent) 45%, var(--hb-border));
	}
	.label {
		color: var(--hb-text-muted);
		font-size: 11px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}
	.value {
		font-size: 1.75rem;
		font-weight: 650;
		font-variant-numeric: tabular-nums;
		margin-top: 0.2rem;
		line-height: 1.1;
	}
	.hint {
		margin-top: 0.25rem;
		color: var(--hb-text-dim);
		font-size: 11px;
	}
</style>
