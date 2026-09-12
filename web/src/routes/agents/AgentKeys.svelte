<!-- Agent credential inventory and one-time bearer display.
     Uses boss-scoped key APIs, auth state and translated console controls. -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { listAgentKeys, mintAgentKey, revokeAgentKey, type AgentKey } from '$lib/api/agent-keys';
  import { auth } from '$lib/stores/auth.svelte';
  import { formatDateTime, t } from '$lib/i18n';
  let { agentId }: { agentId: string } = $props();
  let keys = $state<AgentKey[]>([]);
  let label = $state('');
  let bearer = $state('');
  let copied = $state(false);
  let loading = $state(true);
  let busy = $state(false);
  let error = $state('');
  let confirmId = $state<string | null>(null);
  let active = true;

  async function load(): Promise<void> {
    const connection = auth.connection;
    if (!connection) { loading = false; error = t('top.offline'); return; }
    try { const rows = await listAgentKeys(connection, agentId); if (active) keys = rows; }
    catch (e) { if (active) error = String(e); }
    finally { if (active) loading = false; }
  }
  async function mint(): Promise<void> {
    const connection = auth.connection;
    if (!connection || busy) return;
    busy = true; error = ''; copied = false;
    try {
      const grant = await mintAgentKey(connection, agentId, label.trim());
      if (!active) return;
      bearer = grant.key; label = '';
      await load();
    } catch (e) { if (active) error = String(e); }
    finally { if (active) busy = false; }
  }
  async function revoke(key: AgentKey): Promise<void> {
    const connection = auth.connection;
    if (!connection || busy) return;
    busy = true; error = '';
    try { await revokeAgentKey(connection, agentId, key.id); confirmId = null; await load(); }
    catch (e) { if (active) error = String(e); }
    finally { if (active) busy = false; }
  }
  async function copy(): Promise<void> {
    try { await navigator.clipboard.writeText(bearer); copied = true; }
    catch { error = t('keys.copyFailed'); }
  }
  onMount(() => { void load(); return () => { active = false; bearer = ''; }; });
</script>

<section aria-label={t('keys.title')}>
  <h3>{t('keys.title')}</h3>
  {#if error}<p role="alert">{error}</p>{/if}
  {#if loading}<p>{t('app.loading')}</p>
  {:else}
    {#if keys.length === 0}<p>{t('keys.empty')}</p>{/if}
    <ul>
      {#each keys as key (key.id)}
        <li>
          <strong>{key.label}</strong>
          <small>{t('form.created')}: {formatDateTime(key.created_at)}</small>
          <small>{t('keys.lastUsed')}: {key.last_used_at ? formatDateTime(key.last_used_at) : t('common.never')}</small>
          {#if key.revoked_at}<span>{t('keys.revoked')}</span>
          {:else if confirmId === key.id}
            <p>{t('keys.confirm')}</p>
            <button disabled={busy} onclick={() => revoke(key)}>{t('keys.revoke')}</button>
            <button disabled={busy} onclick={() => confirmId = null}>{t('common.cancel')}</button>
          {:else}<button disabled={busy} onclick={() => confirmId = key.id}>{t('keys.revoke')}</button>{/if}
        </li>
      {/each}
    </ul>
    <button disabled={busy} onclick={() => { error = ''; void load(); }}>{t('common.refresh')}</button>
  {/if}
  {#if bearer}
    <div class="secret" aria-live="polite">
      <p>{t('keys.once')}</p>
      <code>{bearer}</code>
      <button onclick={copy}>{copied ? t('form.copied') : t('form.copy')}</button>
      <button onclick={() => { bearer = ''; copied = false; }}>{t('common.close')}</button>
    </div>
  {:else}
    <form onsubmit={(event) => { event.preventDefault(); void mint(); }}>
      <label>{t('keys.label')}<input bind:value={label} maxlength="100" required disabled={busy} /></label>
      <button disabled={busy || !label.trim()}>{t('keys.mint')}</button>
    </form>
  {/if}
</section>

<style>
  section { border-top: 1px solid var(--hb-border); padding-top: 1rem; min-width: 0; }
  h3 { margin: 0 0 .7rem; font-size: 14px; }
  ul { padding: 0; list-style: none; }
  li { border-bottom: 1px solid var(--hb-border-subtle); padding: .6rem 0; overflow-wrap: anywhere; }
  small { display: block; color: var(--hb-text-muted); margin: .3rem 0; }
  input { display: block; width: 100%; box-sizing: border-box; padding: .5rem; margin: .4rem 0; }
  input, button { color: var(--hb-text); background: var(--hb-bg-panel); border: 1px solid var(--hb-border); border-radius: var(--hb-radius-sm); }
  button { padding: .4rem .65rem; margin: .2rem .3rem .2rem 0; cursor: pointer; }
  button:disabled { opacity: .5; cursor: wait; }
  code { display: block; overflow-wrap: anywhere; user-select: all; }
  .secret { padding: .7rem; background: var(--hb-bg-elevated); margin-top: .7rem; }
  [role='alert'] { color: var(--hb-danger, #b91c1c); overflow-wrap: anywhere; }
</style>
