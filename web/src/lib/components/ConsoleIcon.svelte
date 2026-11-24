<!-- Navigation icons from the approved console mockups.
     Their text labels supply each link's accessible name. -->
<script lang="ts">
	let { name }: { name: string } = $props();
	const paths: Record<string, string> = {
		today: 'M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
		sessions: 'M4 5h16v11H9l-5 4z',
		messages: 'M3 13l3-8h12l3 8v6H3zM3 13h5l1 3h6l1-3h5',
		agents: 'M7 7h10v10H7zM10 3v4M14 3v4M10 17v4M14 17v4M3 10h4M3 14h4M17 10h4M17 14h4',
		delivery: 'M6 16v-5a6 6 0 0 1 12 0v5l2 2H4zM10 21h4',
		projects: 'M3 6h6l2 2h10v11H3z',
		access: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z',
		audit: 'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
		server: 'M4 4h16v6H4zM4 14h16v6H4zM8 7h.01M8 17h.01',
		more: 'M5 12h.01M12 12h.01M19 12h.01',
	};
</script>

<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8"
	stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
	{#if paths[name]}<path d={paths[name]} />{/if}
</svg>
