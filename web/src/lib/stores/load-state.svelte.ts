// Reactive state for the console's standard authenticated data loads.
// Exports LoadState; depends on auth, i18n and API error text.
import { apiErrorMessage } from '$lib/api/types';
import { auth } from './auth.svelte';
import { t } from '$lib/i18n';

export class LoadState {
	loading = $state(true);
	error = $state<string | null>(null);

	async run(
		operation: (client: NonNullable<typeof auth.client>) => Promise<void>,
		offlineMessage?: string
	): Promise<void> {
		const client = auth.client;
		if (!client) {
			this.error = offlineMessage ?? t('top.offline');
			this.loading = false;
			return;
		}
		this.loading = true;
		this.error = null;
		try {
			await operation(client);
		} catch (e) {
			this.error = apiErrorMessage(e);
		} finally {
			this.loading = false;
		}
	}
}
