<script lang="ts">
	import { t } from '$lib/i18n';
	interface Props {
		title: string;
		detail?: string;
	}

	let {
		title,
		detail = t('common.dataWillAppear')
	}: Props = $props();
</script>

<section class="soon">
	<div class="eyebrow">{t('form.endpointUnavailable')}</div>
	<h1>{title}</h1>
	<p>{detail}</p>
</section>

<style>
	.soon {
		max-width: 36rem;
		padding: 2rem 0;
	}
	.eyebrow {
		font-size: 11px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--hb-accent);
		margin-bottom: 0.5rem;
	}
	h1 {
		margin: 0 0 0.5rem;
		font-size: 1.35rem;
		font-weight: 650;
	}
	p {
		margin: 0;
		color: var(--hb-text-muted);
	}
</style>
