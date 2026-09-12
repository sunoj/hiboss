<!-- Project inventory with inline display-name editing and confirmed merges.
     Uses boss-scoped APIs, existing console states, and four-locale copy. -->
<script lang="ts">
  import { onMount } from 'svelte';
  import { auth } from '$lib/stores/auth.svelte';
  import { t, formatDateTime } from '$lib/i18n';
  import { listProjects, patchProject, type ProjectId, type ProjectRecord } from '$lib/api/projects';
  import ErrorState from '$lib/components/ErrorState.svelte';
  import EmptyState from '$lib/components/EmptyState.svelte';
  import Skeleton from '$lib/components/Skeleton.svelte';

  let projects = $state<ProjectRecord[]>([]);
  let loading = $state(true);
  let pending = $state(false);
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

  async function save(project: ProjectRecord, merge = false): Promise<void> {
    if (!auth.connection || pending || loading) return;
    const target = projects.find(p => p.id === targets[project.id]);
    if (merge && (!target || !window.confirm(t('projects.confirm', { source: project.slug, target: target.slug })))) return;
    pending = true;
    error = null;
    try {
      await patchProject(auth.connection, project.id, merge && target
        ? { merge_into: target.id as ProjectId } : { display_name: names[project.id].trim() });
      projects = await listProjects(auth.connection);
      names = Object.fromEntries(projects.map(p => [p.id, p.display_name]));
      targets = {};
    } catch (cause) { error = String(cause); }
    finally { pending = false; }
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
        <h2>{project.slug}</h2>
        <p>{t('projects.aliases')}: {project.aliases.join(', ')}</p>
        <dl>
          <div><dt>{t('nav.sessions')}</dt><dd>{project.session_count}</dd></div>
          <div><dt>{t('form.lastSeen')}</dt><dd>{date(project.last_seen_at)}</dd></div>
          <div><dt>{t('projects.lastPost')}</dt><dd>{date(project.last_post_at)}</dd></div>
        </dl>
        {#if canEdit}
          <div class="actions">
            <label>{t('projects.displayName')}<input bind:value={names[project.id]} maxlength="256" disabled={pending || loading} /></label>
            <button onclick={() => save(project)} disabled={pending || loading || !names[project.id]?.trim() || names[project.id] === project.display_name}>{t('projects.save')}</button>
            <label>{t('projects.mergeInto')}<select aria-label={t('projects.mergeInto')} bind:value={targets[project.id]} disabled={pending || loading}>
              <option value="">{t('projects.choose')}</option>
              {#each projects.filter(p => p.id !== project.id) as target}<option value={target.id}>{target.slug}</option>{/each}
            </select></label>
            <button onclick={() => save(project, true)} disabled={pending || loading || !targets[project.id]}>{t('projects.merge')}</button>
          </div>
        {:else}<p>{project.display_name}</p>{/if}
      </li>
    {/each}</ul>
  {/if}
</section>

<style>
  .page { max-width: 80rem; margin: auto; padding: 1.5rem; }
  header, .actions { display: flex; gap: 1rem; align-items: end; flex-wrap: wrap; }
  header { justify-content: space-between; align-items: center; margin-bottom: 1.5rem; }
  h1 { font-size: 1.3rem; margin: 0; } h2 { font-size: 1rem; overflow-wrap: anywhere; }
  p, dt { color: var(--hb-text-muted); font-size: .8rem; overflow-wrap: anywhere; }
  ul { list-style: none; margin: 0; padding: 0; }
  li { border-top: 1px solid var(--hb-border); padding: 1rem 0; }
  dl { display: flex; flex-wrap: wrap; gap: 1rem 2rem; font-size: .8rem; } dd { margin: .3rem 0; }
  label { display: grid; gap: .4rem; font-size: .8rem; max-width: 100%; }
  input, select, button { border: 1px solid var(--hb-border); background: var(--hb-bg-elevated); color: var(--hb-text); padding: .5rem .8rem; border-radius: var(--hb-radius-sm); min-width: 0; max-width: 100%; }
  button { cursor: pointer; } button:disabled { opacity: .5; cursor: not-allowed; }
</style>
