<!-- Current-boss notification inventory with delivery controls for HiBoss clients.
     Depends on Svelte runes, authenticated API, shared states, and localized components. -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { auth } from '$lib/stores/auth.svelte';
  import { t } from '$lib/i18n';
  import ErrorState from '$lib/components/ErrorState.svelte';
  import EmptyState from '$lib/components/EmptyState.svelte';
  import Skeleton from '$lib/components/Skeleton.svelte';
  import DestinationRow from './DestinationRow.svelte';
  import { NotificationsClient } from './client';
  import type { Destination, DestinationPatch, Inventory } from './types';

  let inventory = $state<Inventory>({ destinations: [], mode: 'off' });
  let loading = $state(true);
  let pending = $state(false);
  let error = $state<string | null>(null);
  let feedback = $state<Record<string, string>>({});
  const readOnly = $derived(auth.connection?.boss?.role === 'viewer');
  const client = $derived(auth.client ? new NotificationsClient(auth.client) : null);
  async function load(): Promise<void> {
    if (pending) return;
    loading = true; error = null;
    try { if (!client) throw new Error(t('top.offline')); inventory = await client.inventory(); }
    catch (cause) { error = cause instanceof Error ? cause.message : String(cause); }
    finally { loading = false; }
  }
  async function mutate(
    action: (api: NotificationsClient) => Promise<unknown>,
    id: string,
    refresh = true
  ): Promise<void> {
    if (pending || loading || readOnly || !client) return;
    pending = true;
    error = null;
    feedback[id] = '';
    try {
      await action(client);
      if (refresh) inventory = await client.inventory();
      else feedback[id] = t('notifications.testSent');
    } catch (cause) {
      feedback[id] = cause instanceof Error ? cause.message : String(cause);
    } finally {
      pending = false;
    }
  }

  function patch(row: Destination, input: DestinationPatch): void {
    void mutate(api => api.patch(row.id, input), row.id);
  }

  onMount(() => { void load(); });
</script>
<section class="page">
  <header>
    <h1>{t('console.delivery')}</h1>
    <button onclick={load} disabled={loading || pending}>{t('common.refresh')}</button>
  </header>
  {#if error}<ErrorState message={error} onRetry={load} />{/if}
  {#if loading}<Skeleton rows={4} />{:else}
    {#if !error && inventory.mode !== 'on'}<aside>{t('notifications.preview')} {t('notifications.testHint')}</aside>{/if}
    {#if readOnly}<p role="note">{t('notifications.readOnly')}</p>{/if}
    {#if inventory.destinations.length === 0 && !error}<EmptyState title={t('notifications.empty')} detail={t('notifications.subtitle')} />{/if}
    <div class="rows">
    {#each inventory.destinations as row (row.id)}
      <DestinationRow {row} mode={inventory.mode} disabled={readOnly || pending || Boolean(error)} feedback={feedback[row.id]}
        onPatch={input => patch(row, input)} onTest={() => { void mutate(api => api.test(row.id), row.id, false); }} />
    {/each}
    </div>
  {/if}
</section>
<style>
  .page { max-width: 80rem; margin: 0 auto; }
  .rows:not(:empty) { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-l); }
  .rows > :global(article + article) { border-block-start: 1px solid var(--hairline); }
  header { display: flex; align-items: start; justify-content: space-between; gap: 1rem; margin-bottom: 1.5rem; }
  h1 { font: var(--t-large); margin: 0; } p { color: var(--hb-text-muted); font-size: 0.85rem; }
  aside { padding: 0.8rem 1rem; margin-bottom: 1rem; border: 1px solid var(--hb-border); background: var(--hb-bg-panel); color: var(--hb-text-muted); font-size: 0.8rem; }
  button { padding: 0.5rem 0.8rem; color: var(--hb-text); background: var(--hb-bg-panel); border: 1px solid var(--hb-border); border-radius: var(--hb-radius-sm); cursor: pointer; }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
