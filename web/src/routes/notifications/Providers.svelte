<!-- Compact admin-only provider inventory and write-only credential creation form.
     Depends on notification API contracts and localized labels. -->
<script lang="ts">
  import { formatDateTime, t } from '$lib/i18n';
  import type { Provider, ProviderInput } from './types';
  let { providers, disabled, onCreate }: { providers: Provider[]; disabled: boolean; onCreate: (input: ProviderInput) => Promise<boolean> } = $props();
  let provider = $state<'telegram' | 'discord'>('telegram');
  let label = $state('');
  let token = $state('');
  let webhook = $state('');
  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    const credentials = { ...(token ? { bot_token: token } : {}), ...(provider === 'discord' && webhook ? { webhook_url: webhook } : {}) };
    try { if (await onCreate({ provider, label, credentials })) label = ''; }
    finally { token = ''; webhook = ''; }
  }
</script>
<details class="providers"><summary>{t('notifications.providers')}</summary>
  <ul>{#each providers as row}<li><strong>{row.label}</strong><span>{row.provider}</span><time>{formatDateTime(row.created_at.includes('T') ? row.created_at : `${row.created_at.replace(' ', 'T')}Z`)}</time></li>{/each}</ul>
  <p>{t('notifications.credentials')}</p>
  <form onsubmit={submit}><fieldset {disabled}>
    <label>{t('notifications.provider')}<select bind:value={provider} onchange={() => { token = ''; webhook = ''; }}><option value="telegram">Telegram</option><option value="discord">Discord</option></select></label>
    <label>{t('notifications.label')}<input bind:value={label} required maxlength="100" /></label>
    <label>{t('notifications.botToken')}<input type="password" bind:value={token} required={provider === 'telegram' || !webhook} autocomplete="new-password" /></label>
    {#if provider === 'discord'}<label>{t('notifications.webhook')}<input type="password" bind:value={webhook} autocomplete="new-password" /></label>{/if}
    <button type="submit">{t('notifications.addProvider')}</button>
  </fieldset></form>
</details>
<style>
  .providers { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid var(--hb-border); }
  summary { cursor: pointer; font-weight: 600; } ul { list-style: none; padding: 0; }
  li { display: flex; flex-wrap: wrap; gap: 1rem; font-size: 0.8rem; padding: 0.6rem 0; overflow-wrap: anywhere; }
  span, time, p { color: var(--hb-text-muted); font-size: 0.8rem; }
  fieldset { border: 0; padding: 0; display: flex; align-items: end; flex-wrap: wrap; gap: 0.75rem; }
  label { display: grid; gap: 0.4rem; font-size: 0.8rem; flex: 1 1 10rem; }
  input, select, button { min-width: 0; padding: 0.6rem; color: var(--hb-text); background: var(--hb-bg-panel); border: 1px solid var(--hb-border); border-radius: var(--hb-radius-sm); }
  button { cursor: pointer; } fieldset:disabled { opacity: 0.5; }
</style>
