<!-- Project inventory with inline display-name editing and confirmed merges.
     Uses boss-scoped APIs, existing console states, and four-locale copy. -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { auth } from '$lib/stores/auth.svelte';
  import { t, formatDateTime } from '$lib/i18n';
  import { listProjects, patchProject, type ProjectId, type ProjectRecord } from '$lib/api/projects';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import ErrorState from '$lib/components/ErrorState.svelte';
  import EmptyState from '$lib/components/EmptyState.svelte';
  import Skeleton from '$lib/components/Skeleton.svelte';

  let projects = $state<ProjectRecord[]>([]);
  let loading = $state(true);
  let pending = $state(false);
  let confirm = $state<{ source: ProjectRecord; target: ProjectRecord } | null>(null);
  let error = $state<string | null>(null);
  let names = $state<Record<string, string>>({});
  let targets = $state<Record<string, string>>({});
  const canEdit = $derived(auth.connection?.boss?.role !== 'viewer');

  async function load(): Promise<void> {
    if (!auth.connection || pending) return;
    loading = true;
    error = null;
    try {
      projects = await listProjects(auth.connection);
      names = Object.fromEntries(projects.map(p => [p.id, p.display_name]));
      targets = {};
    } catch (cause) { error = String(cause); }
    finally { loading = false; }
  }

  async function save(project: ProjectRecord, target?: ProjectRecord): Promise<void> {
    if (!auth.connection || pending || loading) return;
    pending = true;
    error = null;
    try {
      await patchProject(auth.connection, project.id, target
        ? { merge_into: target.id as ProjectId } : { display_name: names[project.id].trim() });
      projects = await listProjects(auth.connection);
      names = Object.fromEntries(projects.map(p => [p.id, p.display_name]));
      targets = {};
    } catch (cause) { error = String(cause); }
    finally { pending = false; }
  }

  function confirmMerge(source: ProjectRecord): void {
    const target = projects.find(p => p.id === targets[source.id] && p.id !== source.id);
    if (target) confirm = { source, target };
  }

  function date(value: string | null): string {
    return value ? formatDateTime(value.includes('T') ? value : `${value.replace(' ', 'T')}Z`) : t('common.never');
  }
  onMount(() => { void load(); });
</script>

<section class="page">
  <header><div><h1>{t('nav.projects')}</h1><p>{t('projects.description')}</p></div>
    <button onclick={load} disabled={loading || pending}>{t('common.refresh')}</button></header>
  {#if error}<ErrorState message={error} onRetry={load} />{/if}
  {#if loading && !projects.length}<Skeleton rows={4} />
  {:else if !error && !projects.length}<EmptyState title={t('projects.empty')} detail={t('projects.description')} />
  {:else}
    <ul>{#each projects as project (project.id)}
      <li>
        <div class="identity">
          <span class="tile" aria-hidden="true">{project.display_name.slice(0, 1).toUpperCase()}</span>
          <div><h2>{project.display_name}</h2><code>{project.slug}</code></div>
        </div>
        {#if project.aliases.length}<p>{t('projects.aliases')}: {project.aliases.join(', ')}</p>{/if}
        <dl>
          <div><dt>{t('nav.sessions')}</dt><dd><a href={'/sessions?project=' + encodeURIComponent(project.slug)}>{project.session_count}</a></dd></div>
          <div><dt>{t('form.lastSeen')}</dt><dd>{date(project.last_seen_at)}</dd></div>
          <div><dt>{t('projects.lastPost')}</dt><dd>{date(project.last_post_at)}</dd></div>
        </dl>
        {#if canEdit}
          <details>
            <summary>{t('console.details')}</summary>
            <div class="actions">
            <label>{t('projects.displayName')}<input bind:value={names[project.id]} maxlength="256" disabled={pending || loading} /></label>
            <button onclick={() => save(project)} disabled={pending || loading || !names[project.id]?.trim() || names[project.id] === project.display_name}>{t('projects.save')}</button>
            <label>{t('projects.mergeInto')}<select aria-label={t('projects.mergeInto')} bind:value={targets[project.id]} disabled={pending || loading}>
              <option value="">{t('projects.choose')}</option>
              {#each projects.filter(p => p.id !== project.id) as target}<option value={target.id}>{target.slug}</option>{/each}
            </select></label>
            <button onclick={() => confirmMerge(project)} disabled={pending || loading || !targets[project.id]}>{t('projects.merge')}</button>
            </div>
          </details>
        {/if}
      </li>
    {/each}</ul>
  {/if}
  {#if confirm}
    {@const { source, target } = confirm}
    <ConfirmDialog action={t('projects.merge')}
      message={t('projects.confirm', { source: source.slug, target: target.slug })}
      onConfirm={() => save(source, target)} onClose={() => { confirm = null; }} />
  {/if}
</section>

<style>
  .page { max-width: 80rem; margin: auto; }
  header, .actions { display: flex; gap: 1rem; align-items: end; flex-wrap: wrap; }
  header { justify-content: space-between; align-items: center; margin-bottom: 1.5rem; }
  h1 { font: var(--t-large); margin: 0; } h2 { font: var(--t-headline); margin: 0; overflow-wrap: anywhere; }
  p, dt { color: var(--hb-text-muted); font-size: .8rem; overflow-wrap: anywhere; }
  ul { list-style: none; margin: 0; padding: 0; background: var(--surface);
    border: 1px solid var(--border); border-radius: var(--r-l); container-type: inline-size; }
  li { padding: 12px 16px; }
  li + li { border-block-start: 1px solid var(--hairline); }
  .identity { display: flex; gap: 12px; align-items: center; }
  .tile { display: grid; place-items: center; flex: 0 0 var(--tile-row); height: var(--tile-row);
    border-radius: var(--r-m); background: var(--neutral-soft); }
  code { font: var(--t-mono); color: var(--text-3); overflow-wrap: anywhere; }
  summary { min-height: var(--hit); cursor: pointer; color: var(--live); }
  dl a { color: var(--live); text-decoration: underline; }
  @container (width < 600px) {
    dl, dl div { display: grid; gap: 4px 12px; }
    dl div { grid-template-columns: minmax(96px, 35%) minmax(0, 1fr); }
    .actions { display: grid; }
  }
  dl { display: flex; flex-wrap: wrap; gap: 1rem 2rem; font-size: .8rem; } dd { margin: .3rem 0; }
  label { display: grid; gap: .4rem; font-size: .8rem; max-width: 100%; }
  input, select, button { min-height: var(--hit); border: 1px solid var(--hb-border); background: var(--hb-bg-elevated); color: var(--hb-text); padding: .5rem .8rem; border-radius: var(--hb-radius-sm); min-width: 0; max-width: 100%; }
  button { cursor: pointer; } button:disabled { opacity: .5; cursor: not-allowed; }
</style>
