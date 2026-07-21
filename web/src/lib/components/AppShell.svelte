<script lang="ts">
	import type { Snippet } from 'svelte';
	import SideNav from './SideNav.svelte';
	import TopBar from './TopBar.svelte';
	import ToastHost from './ToastHost.svelte';

	interface Props {
		connected?: boolean;
		children: Snippet;
	}

	let { connected = true, children }: Props = $props();
</script>

<div class="shell">
	<SideNav />
	<div class="main">
		<TopBar {connected} />
		<main class="content">
			{@render children()}
		</main>
	</div>
	<ToastHost />
</div>

<style>
	.shell {
		display: flex;
		min-height: 100vh;
		background: var(--hb-bg);
	}
	.main {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
	}
	.content {
		padding: 1rem 1.15rem 2rem;
		flex: 1;
	}
</style>
