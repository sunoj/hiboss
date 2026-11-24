<!-- Account destinations and browser sign-out.
     Used in the desktop menu and the More screen. -->
<script lang="ts">
	import { goto } from '$app/navigation';
	import { auth } from '$lib/stores/auth.svelte';
	import { t } from '$lib/i18n';
	import ConsolePreferences from './ConsolePreferences.svelte';

	let signingOut = $state(false);

	async function signOut() {
		if (signingOut) return;
		signingOut = true;
		try { await auth.client?.revokeOwnToken(); } catch { /* Older servers may lack revocation. */ }
		finally {
			auth.signOut();
			await goto('/connect');
		}
	}
</script>

<div class="actions">
	<a href="/devices">{t('nav.devices')}</a>
	<ConsolePreferences />
	<button type="button" disabled={signingOut} onclick={signOut}>{t('top.signOut')}</button>
</div>

<style>
	.actions { display: grid; gap: 8px; }
	a, button { min-height: var(--hit); padding: 10px; border-radius: 8px; }
	button { text-align: start; background: var(--surface-2); border: 1px solid var(--border); }
</style>
