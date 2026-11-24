<!-- Native modal confirmation with focus restoration.
     The caller owns the destructive operation and its result. -->
<script lang="ts">
	import { t } from '$lib/i18n';

	let { message, action, onConfirm, onClose }: {
		message: string; action: string; onConfirm: () => void; onClose: () => void;
	} = $props();
	let dialog: HTMLDialogElement;
	$effect(() => {
		const opener = document.activeElement;
		dialog.showModal();
		return () => {
			dialog.close();
			if (opener instanceof HTMLElement) opener.focus();
		};
	});
</script>

<dialog bind:this={dialog} onclose={onClose} aria-label={action}>
	<p>{message}</p>
	<form method="dialog">
		<button>{t('common.cancel')}</button>
		<button type="button" class="danger" onclick={() => { onClose(); onConfirm(); }}>{action}</button>
	</form>
</dialog>

<style>
	dialog { width: min(calc(100% - 32px), 440px); border: 1px solid var(--border); border-radius: var(--r-l);
		color: var(--ink); background: var(--surface); box-shadow: var(--overlay); }
	dialog::backdrop { background: var(--scrim); }
	form { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: 8px; }
	button { min-height: var(--hit); padding: 8px 12px; border: 1px solid var(--field-border);
		background: var(--surface); border-radius: var(--r-s); }
	.danger { color: var(--danger); }
</style>
