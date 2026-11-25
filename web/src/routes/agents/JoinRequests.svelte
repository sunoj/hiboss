<!-- Lists pending device enrolment and records one approval or rejection.
     Join credentials are delivered by the server to the originating machine. -->
<script lang="ts">
	import type { JoinRequest } from '$lib/api/client';
	import { auth } from '$lib/stores/auth.svelte';
	import { apiErrorMessage } from '$lib/api/types';
	import { formatRelativeTime, t } from '$lib/i18n';

	let { requests, onResolved }: { requests: JoinRequest[]; onResolved: (id: string) => void } = $props();
	let pending = $state<string | null>(null);
	let result = $state('');
	let error = $state('');

	async function resolve(id: string, action: 'approve' | 'reject') {
		const client = auth.client;
		if (!client || pending) return;
		pending = id;
		error = '';
		result = '';
		try {
			await client.resolveJoin(id, action);
			result = t(action === 'approve' ? 'console.joinApproved' : 'console.joinRejected');
			onResolved(id);
		} catch (failure) {
			error = apiErrorMessage(failure);
		} finally {
			pending = null;
		}
	}
</script>

<h1>{t('console.joinRequests')}</h1>
{#if result}<p role="status">{result}</p>{/if}
{#if error}<p role="alert">{error}</p>{/if}
{#if !requests.length}<p>{t('console.noJoinRequests')}</p>{/if}
{#each requests as request (request.id)}
	<article aria-label={request.device_label}>
		<h2>{request.device_label}</h2>
		<p>{request.device_host} · {formatRelativeTime(request.created_at)}</p>
		<p>{request.profiles.map((profile) => profile.profile).filter(Boolean).join(', ')}</p>
		<button disabled={pending !== null} onclick={() => resolve(request.id, 'approve')}>
			{t('console.approve')}
		</button>
		<button disabled={pending !== null} onclick={() => resolve(request.id, 'reject')}>{t('console.reject')}</button>
	</article>
{/each}

<style>
	article { background: var(--surface); border: 1px solid var(--border); padding: 12px; border-radius: var(--r-m); }
	h2 { font: var(--t-headline); }
	button { min-height: var(--hit); }
</style>
