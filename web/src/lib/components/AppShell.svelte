<!-- Console shell arranging shared navigation, header, and routed content.
     Depends on SideNav, TopBar, and ToastHost. -->
<script lang="ts">
	import type { Snippet } from 'svelte';
	import SideNav from './SideNav.svelte';
	import AccountActions from './AccountActions.svelte';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import ToastHost from './ToastHost.svelte';

	interface Props {
		children: Snippet;
	}

	let { children }: Props = $props();
</script>

<a class="skip" href="#main">{t('console.skip')}</a>
<div class="shell">
	<SideNav />
	<div class="main">
		<details class="account">
			<summary>{auth.connection?.boss?.name} · {auth.connection?.boss?.role}</summary>
			<div class="menu"><AccountActions /></div>
		</details>
		<main class="content" id="main">
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
		padding: 24px 32px 32px;
		flex: 1;
	}

	.account { align-self: flex-end; margin: 16px 32px 0; position: relative; z-index: 5; }
	summary { cursor: pointer; min-height: var(--hit); padding: 10px; }
	.menu { position: absolute; inset-inline-end: 0; min-width: 220px; background: var(--surface);
		border: 1px solid var(--border); border-radius: var(--r-m); padding: 12px; box-shadow: var(--overlay); }
	.skip { position: fixed; inset-block-start: 8px; inset-inline-start: 8px; background: var(--surface);
		transform: translateY(-150%); z-index: 30; padding: 8px; }
	.skip:focus { transform: none; }
	@media (max-width: 1023px) {
		.account { display: none; }
		.content { padding: 20px 16px calc(64px + env(safe-area-inset-bottom)); }
	}
</style>
