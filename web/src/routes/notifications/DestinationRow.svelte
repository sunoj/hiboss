<!-- One boss-owned notification destination with accessible per-row controls.
     Depends on typed destination contracts and translated labels. -->
<script lang="ts">
  import { t } from '$lib/i18n';
  import { KIND_ICONS, PRIORITIES, targetLabel, type Destination, type DestinationPatch, type Mode } from './types';
  let { row, mode, disabled, feedback, onPatch, onTest }: {
    row: Destination; mode: Mode; disabled: boolean; feedback?: string;
    onPatch: (patch: DestinationPatch) => void; onTest: () => void;
  } = $props();
  const target = $derived(targetLabel(row));
  const testHint = $derived(mode !== 'on' ? t('notifications.testHint') : row.kind === 'native_live' ? t('notifications.nativeHint') : '');
</script>
<article aria-label={row.label}>
  <div class="identity">
    <span class="icon" aria-label={t(`notifications.${row.kind}`)}>{KIND_ICONS[row.kind]}</span>
    <div>
      <strong>{row.label}</strong>
      <p>{t(`notifications.${row.kind}`)}{#if target} · {target}{/if}</p>
    </div>
    <span class="routes">{t('notifications.routes', { count: row.route_count })}</span>
  </div>
  <div class="controls">
    <label><input type="checkbox" role="switch" checked={row.enabled === 1} {disabled} onchange={(event) => onPatch({ enabled: event.currentTarget.checked })} />{t('notifications.enabled')}</label>
    <fieldset {disabled}><legend>{t('notifications.priority')}</legend><div class="segments">
      {#each PRIORITIES as priority}<button type="button" aria-pressed={row.min_priority === priority} onclick={() => onPatch({ min_priority: priority })}>{t(`notifications.${priority}`)}</button>{/each}
    </div></fieldset>
    <label><input type="checkbox" role="switch" checked={row.honours_quiet_hours === 1} {disabled} onchange={(event) => onPatch({ honours_quiet_hours: event.currentTarget.checked })} />{t('notifications.quiet')}</label>
    {#if !testHint}<button type="button" {disabled} onclick={onTest}>{t('notifications.test')}</button>{/if}
  </div>
  {#if testHint && row.kind === 'native_live' && mode === 'on'}<p class="hint">{testHint}</p>{/if}
  {#if feedback}<p class="feedback" role="status">{feedback}</p>{/if}
</article>
<style>
  article { padding: 12px 16px; }
  strong { font: var(--t-headline); }
  .identity, .controls { display: flex; align-items: center; flex-wrap: wrap; gap: 1rem; }
  .icon { font-size: 1.2rem; width: var(--tile-row); height: var(--tile-row); display: grid;
    place-items: center; border-radius: var(--r-m); background: var(--neutral-soft); }
  .identity div { flex: 1; min-width: 9rem; overflow-wrap: anywhere; }
  p { margin: 0.25rem 0 0; color: var(--hb-text-muted); font-size: 0.8rem; }
  .routes { font-size: 0.8rem; color: var(--hb-text-muted); overflow-wrap: anywhere; }
  .controls { margin-top: 1rem; gap: 1rem 1.5rem; }
  label { display: flex; gap: 0.4rem; align-items: center; font-size: 0.8rem; }
  input { accent-color: var(--hb-accent); width: 1rem; height: 1rem; }
  fieldset { padding: 0; margin: 0; border: 0; }
  legend { font-size: 0.7rem; color: var(--hb-text-muted); margin-bottom: 0.3rem; }
  .segments { display: flex; flex-wrap: wrap; }
  button { min-height: var(--hit); padding: 0.45rem 0.65rem; border: 1px solid var(--hb-border); background: var(--hb-bg-panel); color: var(--hb-text); border-radius: var(--hb-radius-sm); cursor: pointer; }
  .segments button { border-radius: 0; }
  button[aria-pressed='true'] { color: var(--hb-bg); background: var(--hb-accent); }
  button:disabled, fieldset:disabled, input:disabled { opacity: 0.55; cursor: not-allowed; }
  .feedback, .hint { margin-top: 0.75rem; }
</style>
