<!-- Creates Telegram or Discord destinations using credential-free provider choices.
     Depends on notification contracts and shared translated form labels. -->
<script lang="ts">
  import { t } from '$lib/i18n';
  import type { Provider, DestinationInput, ProviderId } from './types';
  let { providers, disabled, onCreate }: { providers: Provider[]; disabled: boolean; onCreate: (input: DestinationInput) => Promise<boolean> } = $props();
  let providerId = $state('');
  let label = $state('');
  let target = $state('');
  let thread = $state('');
  const provider = $derived(providers.find(row => row.id === providerId));
  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!provider || disabled) return;
    const input: DestinationInput = { label, provider_id: provider.id as ProviderId,
      kind: provider.provider === 'telegram' ? 'telegram_chat' : 'discord_channel',
      target: provider.provider === 'telegram' ? { chat_id: target, ...(thread ? { message_thread_id: Number(thread) } : {}) }
        : { channel_id: target, ...(thread ? { thread_id: thread } : {}) } };
    if (await onCreate(input)) { label = ''; target = ''; thread = ''; }
  }
</script>
<details><summary>{t('notifications.add')}</summary>
  {#if providers.length === 0}<p>{t('notifications.noProviders')}</p>{:else}
    <form onsubmit={submit}><fieldset {disabled}>
      <label>{t('notifications.provider')}<select bind:value={providerId} required><option value="" disabled>{t('notifications.provider')}</option>{#each providers as row}<option value={row.id}>{row.label} · {row.provider}</option>{/each}</select></label>
      <label>{t('notifications.label')}<input bind:value={label} required maxlength="100" /></label>
      <label>{t('notifications.target')}<input bind:value={target} required pattern={provider?.provider === 'telegram' ? '-?[0-9]+' : '[0-9]+'} /></label>
      <label>{t('notifications.thread')}<input bind:value={thread} pattern="[1-9][0-9]*" /></label>
      <button type="submit" disabled={!provider}>{t('common.create')}</button>
    </fieldset></form>
  {/if}
</details>
<style>
  details { border-top: 1px solid var(--hb-border); padding: 1rem 0; }
  summary { cursor: pointer; font-weight: 600; }
  fieldset { border: 0; padding: 1rem 0 0; display: flex; align-items: end; flex-wrap: wrap; gap: 1rem; }
  label { display: grid; gap: 0.4rem; font-size: 0.8rem; flex: 1 1 10rem; }
  input, select, button { min-width: 0; padding: 0.6rem; color: var(--hb-text); background: var(--hb-bg-panel); border: 1px solid var(--hb-border); border-radius: var(--hb-radius-sm); }
  button, summary { cursor: pointer; } button:disabled, fieldset:disabled { opacity: 0.5; } p { color: var(--hb-text-muted); }
</style>
