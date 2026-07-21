<script lang="ts">
	import type { HealthTone } from './doctor-helpers';
	import { healthDetail, healthLabel } from './doctor-helpers';

	interface Props {
		dbOk: boolean;
		meOk: boolean;
	}

	let { dbOk, meOk }: Props = $props();

	const tone = $derived<HealthTone>(
		dbOk && meOk ? 'ok' : dbOk || meOk ? 'degraded' : 'fail'
	);
	const label = $derived(healthLabel(tone));
	const detail = $derived(healthDetail(dbOk, meOk));
</script>

<div
	class="beacon"
	class:ok={tone === 'ok'}
	class:degraded={tone === 'degraded'}
	class:fail={tone === 'fail'}
	role="status"
	aria-label={`System ${label}: ${detail}`}
>
	<span class="orb" aria-hidden="true"></span>
	<div class="copy">
		<div class="label">{label}</div>
		<div class="detail">{detail}</div>
		<ul class="probes">
			<li class:pass={dbOk} class:fail={!dbOk}>
				<span class="dot" aria-hidden="true"></span>
				Database
			</li>
			<li class:pass={meOk} class:fail={!meOk}>
				<span class="dot" aria-hidden="true"></span>
				API /me
			</li>
		</ul>
	</div>
</div>

<style>
	.beacon {
		display: flex;
		align-items: center;
		gap: 1.1rem;
		background: var(--hb-bg-panel);
		border: 1px solid var(--hb-border);
		border-radius: var(--hb-radius);
		padding: 1.1rem 1.25rem;
		box-shadow: var(--hb-shadow);
		min-height: 7.5rem;
	}
	.ok {
		border-color: color-mix(in srgb, var(--hb-success) 45%, var(--hb-border));
	}
	.degraded {
		border-color: color-mix(in srgb, var(--hb-warning) 45%, var(--hb-border));
	}
	.fail {
		border-color: color-mix(in srgb, var(--hb-danger) 45%, var(--hb-border));
	}
	.orb {
		width: 3.25rem;
		height: 3.25rem;
		border-radius: 50%;
		flex-shrink: 0;
		background: var(--hb-text-dim);
		box-shadow: 0 0 0 6px color-mix(in srgb, var(--hb-text-dim) 18%, transparent);
	}
	.ok .orb {
		background: var(--hb-success);
		box-shadow: 0 0 0 6px color-mix(in srgb, var(--hb-success) 22%, transparent);
	}
	.degraded .orb {
		background: var(--hb-warning);
		box-shadow: 0 0 0 6px color-mix(in srgb, var(--hb-warning) 22%, transparent);
	}
	.fail .orb {
		background: var(--hb-danger);
		box-shadow: 0 0 0 6px color-mix(in srgb, var(--hb-danger) 22%, transparent);
	}
	.copy {
		min-width: 0;
	}
	.label {
		font-size: 1.35rem;
		font-weight: 700;
		letter-spacing: -0.02em;
		line-height: 1.15;
	}
	.detail {
		margin-top: 0.2rem;
		color: var(--hb-text-muted);
		font-size: 12px;
		font-family: var(--hb-font-mono);
	}
	.probes {
		list-style: none;
		margin: 0.65rem 0 0;
		padding: 0;
		display: flex;
		flex-wrap: wrap;
		gap: 0.55rem 1rem;
	}
	.probes li {
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 11px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		color: var(--hb-text-dim);
	}
	.probes .dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--hb-text-dim);
	}
	.probes .pass {
		color: var(--hb-success);
	}
	.probes .pass .dot {
		background: var(--hb-success);
	}
	.probes .fail {
		color: var(--hb-danger);
	}
	.probes .fail .dot {
		background: var(--hb-danger);
	}
</style>
