<!-- Grouped navigation row with a monogram, two text lines and a timestamp.
     Parents own the grouped surface and inter-row separators. -->
<script lang="ts">
	import { formatRelativeTime } from '$lib/api/mappers';
	import { formatDateTime } from '$lib/i18n';

	let { href, title, subtitle, tile, datetime, live = false }: {
		href: string; title: string; subtitle: string; tile: string; datetime: string; live?: boolean;
	} = $props();
</script>

<a {href}>
	<span class="tile" class:live aria-hidden="true">{tile}</span>
	<span class="text">
		<strong title={title}>{title}</strong>
		<span title={subtitle}>{subtitle}</span>
	</span>
	<time {datetime} title={formatDateTime(datetime)}>{formatRelativeTime(datetime)}</time>
</a>

<style>
	a { display: flex; align-items: center; gap: 12px; padding: 12px 16px; min-height: 56px; }
	a:hover { background: var(--surface-2); }
	a:focus-visible { outline-offset: -2px; }
	.tile { flex: 0 0 var(--tile-row); height: var(--tile-row); display: grid; place-items: center;
		border-radius: var(--r-m); background: var(--neutral-soft); font-weight: 600; }
	.live { color: var(--live); background: var(--live-soft); }
	.text { display: grid; min-width: 0; flex: 1; }
	.text > * { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	strong { font: var(--t-callout); font-weight: 600; }
	.text span, time { color: var(--text-3); font: var(--t-footnote); }
	time { white-space: nowrap; }
</style>
