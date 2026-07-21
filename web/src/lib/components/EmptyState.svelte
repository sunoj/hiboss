<script lang="ts">
	interface Props {
		title?: string;
		detail?: string;
	}

	let {
		title = 'Nothing here yet',
		detail = 'Data will appear when agents start reporting.'
	}: Props = $props();
</script>

<div class="empty" role="status">
	<div class="title">{title}</div>
	<p>{detail}</p>
</div>

<style>
	.empty {
		padding: 1.5rem 1rem;
		text-align: center;
		color: var(--hb-text-muted);
		border: 1px dashed var(--hb-border);
		border-radius: var(--hb-radius);
		background: var(--hb-bg-input);
	}
	.title {
		font-weight: 650;
		color: var(--hb-text);
		margin-bottom: 0.25rem;
	}
	p {
		margin: 0;
		font-size: 12px;
	}
</style>
