// Reproduces phase 3a wire, historical merge, targeting and validation failures.
// Exercises Worker endpoints and verifies durable D1 relationships and audit rows.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, getTestAgentId, seedDatabase } from '../test-helpers';
import type { Project } from './index';
import { mergeStatements } from './merge';

beforeAll(seedDatabase);
const post = (path: string, body: Record<string, unknown>): Promise<Response> => SELF.fetch(`https://test.local/api/${path}`, {
  method: 'POST', headers: authHeaders(), body: JSON.stringify(body),
});
const put = (project: string, body: Record<string, unknown>): Promise<Response> => SELF.fetch(`https://test.local/api/progress/teams/${encodeURIComponent(project)}`, {
  method: 'PUT', headers: authHeaders(), body: JSON.stringify(body),
});

it('prefers additive identity metadata over legacy project text', async () => {
  for (const path of ['sessions', 'progress']) {
    const response = await post(path, { id: 'additive-session', body: 'additive', project: 'ignored-wire-slug',
      project_identity: { slug: 'preferred-slug', aliases: ['preferred-checkout'] } });
    expect(response.status).toBe(201);
  }
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM projects WHERE slug = 'ignored-wire-slug'").first('n')).toBe(0);
  expect(await env.DB.prepare("SELECT p.slug AS project FROM progress_posts pp JOIN projects p ON p.id = pp.project_id WHERE body = 'additive'").first('project')).toBe('preferred-slug');
});

it('merges origin/checkout history, registers the hook and permits its next send', async () => {
  await post('sessions', { id: 'audit-old', label: 'audit-repo/main', cwd: '/work/audit-checkout' });
  await post('progress', { body: 'audit-history', project: 'audit-checkout', session_id: 'audit-old' });
  const absorbed = await env.DB.prepare("SELECT id FROM projects WHERE slug = 'audit-checkout'").first<string>('id');
  await env.DB.prepare("INSERT INTO bosses (id, name) VALUES ('merge-boss', 'Merge Boss')").run();
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, label, target) VALUES ('merge-dest', 'merge-boss', 'native_live', 'Merge', '{}')").run();
  await env.DB.prepare("INSERT INTO destination_routes (id, destination_id, project_id) VALUES ('merge-route', 'merge-dest', ?)").bind(absorbed).run();
  const response = await post('sessions', { id: 'audit-new', project: 'audit-repo',
    project_identity: { slug: 'audit-repo', aliases: ['audit-checkout'] } });
  expect(response.status).toBe(201);
  const winner = await env.DB.prepare("SELECT id FROM projects WHERE slug = 'audit-repo'").first<string>('id');
  for (const [table, id] of [['sessions', 'audit-old'], ['sessions', 'audit-new'], ['destination_routes', 'merge-route']]) {
    expect(await env.DB.prepare(`SELECT project_id FROM ${table} WHERE id = ?`).bind(id).first('project_id')).toBe(winner);
  }
  expect(await env.DB.prepare("SELECT project_id FROM progress_posts WHERE body = 'audit-history'").first('project_id')).toBe(winner);
  expect(await env.DB.prepare("SELECT project_id FROM project_aliases WHERE alias = 'audit-checkout'").first('project_id')).toBe(winner);
  const audit = await env.DB.prepare("SELECT details FROM audit_log WHERE action = 'project.merge' AND resource_id = ?").bind(winner).first<string>('details');
  expect(JSON.parse(audit!)).toEqual({ absorbed_ids: [absorbed] });
  expect((await post('messages', { body: 'hook recovered', session_id: 'audit-new' })).status).toBe(201);
  expect((await env.DB.prepare('PRAGMA foreign_key_check').all()).results).toEqual([]);
});

it('selects the oldest project when the presented slug has no matching alias', async () => {
  await post('progress', { body: 'older', project: 'older-project' });
  await post('progress', { body: 'newer', project: 'newer-project' });
  await post('progress', { body: 'third', project: 'third-project' });
  await env.DB.prepare("UPDATE projects SET created_at = '2000-01-01' WHERE slug = 'older-project'").run();
  const response = await post('progress', { body: 'merged oldest', project_identity: { slug: 'unseen-slug', aliases: ['newer-project', 'older-project', 'third-project'] } });
  expect(response.status).toBe(201);
  expect((await response.json() as { project: string }).project).toBe('older-project');
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM projects WHERE slug IN ('newer-project', 'third-project')").first('n')).toBe(0);
});

it('rolls back relationship moves, deletion and merge audit together on batch failure', async () => {
  await post('progress', { body: 'rollback winner', project: 'rollback-winner' });
  await post('progress', { body: 'rollback loser', project: 'rollback-loser' });
  const winner = await env.DB.prepare("SELECT id, slug FROM projects WHERE slug = 'rollback-winner'").first<Project>();
  const loser = await env.DB.prepare("SELECT id, slug FROM projects WHERE slug = 'rollback-loser'").first<Project>();
  await expect(env.DB.batch([
    ...mergeStatements(env.DB, winner!, [loser!], getTestAgentId()),
    env.DB.prepare('INSERT INTO projects (id, slug, display_name) VALUES (?, ?, ?)').bind(winner!.id, winner!.slug, 'duplicate'),
  ])).rejects.toThrow(/UNIQUE/);
  expect(await env.DB.prepare('SELECT id FROM projects WHERE id = ?').bind(loser!.id).first('id')).toBe(loser!.id);
  expect(await env.DB.prepare("SELECT project_id FROM project_aliases WHERE alias = 'rollback-loser'").first('project_id')).toBe(loser!.id);
  expect(await env.DB.prepare("SELECT project_id FROM progress_posts WHERE body = 'rollback loser'").first('project_id')).toBe(loser!.id);
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM audit_log WHERE action = 'project.merge' AND resource_id = ?").bind(winner!.id).first('n')).toBe(0);
});

it('targets both the displayed canonical label and the stored label exactly or by prefix', async () => {
  await post('sessions', { id: 'visible-target', label: 'HiBoss/main' });
  const listed = await SELF.fetch('https://test.local/api/sessions', { headers: authHeaders() });
  const sessions = await listed.json() as { sessions: { id: string; label: string }[] };
  expect(sessions.sessions.find(row => row.id === 'visible-target')?.label).toBe('hiboss/main');
  for (const to of ['hiboss/main', 'hiboss', 'HiBoss/main', 'HiBoss']) {
    const response = await post('messages', { body: 'label delivery', to });
    expect(response.status).toBe(201);
    const message = await response.json() as { id: string };
    expect(await env.DB.prepare('SELECT target_session_id FROM messages WHERE id = ?').bind(message.id).first('target_session_id')).toBe('visible-target');
  }
});

it('round-trips migration collision slugs through progress, registration and team updates', async () => {
  const slug = 'collision--4162';
  await env.DB.prepare('INSERT INTO projects (id, slug, display_name) VALUES (?, ?, ?)').bind(slug, slug, 'Collision').run();
  await env.DB.prepare("INSERT INTO project_aliases (alias, project_id, source) VALUES (?, ?, 'explicit')").bind(slug, slug).run();
  expect((await put(slug, { display_name: 'Updated' })).status).toBe(200);
  expect((await post('sessions', { id: 'collision-session', project: slug })).status).toBe(201);
  const response = await post('progress', { body: 'collision post', project: slug });
  expect((await response.json() as { project: string }).project).toBe(slug);
  expect(await env.DB.prepare('SELECT display_name FROM projects WHERE id = ?').bind(slug).first('display_name')).toBe('Updated');
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM projects WHERE slug = 'collision-4162'").first('n')).toBe(0);
});

it('groups normalized first sightings and treats explicit checkout aliases as grouping assertions', async () => {
  await post('progress', { body: 'spaces', project: 'Audit New Space' });
  const normalized = await post('progress', { body: 'normalized', project: 'audit-new-space' });
  expect((await normalized.json() as { project: string }).project).toBe('audit-new-space');
  const explicit = await post('progress', { body: 'explicit alias', project_identity: { slug: 'elsewhere', aliases: ['audit-new-space'] } });
  expect((await explicit.json() as { project: string }).project).toBe('audit-new-space');
});

it('applies identical alias limits to text, object and team paths', async () => {
  for (const alias of ['x'.repeat(257), 'bad\nname', 'bad\u0000name', 'bad\u007fname', 'bad\u0085name']) {
    for (const project of [alias, { slug: 'valid', aliases: [alias] }, { slug: alias, aliases: [] }]) {
      for (const path of ['sessions', 'progress']) {
        expect((await post(path, { id: 'invalid', body: 'invalid', project })).status).toBe(400);
      }
    }
    expect((await put(alias, {})).status).toBe(400);
  }
  expect((await post('progress', { body: 'limit', project: 'x'.repeat(256) })).status).toBe(201);
  const generated = await post('progress', { body: 'unicode limit', project: '项'.repeat(256) });
  const { project } = await generated.json() as { project: string };
  expect(project.length).toBeLessThanOrEqual(256);
  const repeated = await post('progress', { body: 'unicode round trip', project });
  expect(repeated.status).toBe(201);
  expect((await repeated.json() as { project: string }).project).toBe(project);
});

it('caps identity metadata and profile display names', async () => {
  for (const [key, limit] of [['display_name', 256], ['repo_url', 2048]] as const) {
    for (const path of ['sessions', 'progress']) {
      expect((await post(path, { id: 'metadata', body: 'metadata', project_identity: { slug: 'metadata', aliases: [], [key]: 'x'.repeat(limit + 1) } })).status).toBe(400);
      expect((await post(path, { id: 'metadata', body: 'metadata', project_identity: { slug: 'metadata', aliases: [], [key]: 'x'.repeat(limit) } })).status).toBe(201);
    }
  }
  expect((await put('metadata', { display_name: 'x'.repeat(257) })).status).toBe(400);
});

it('returns 409 text on duplicate API key creation', async () => {
  await env.DB.prepare("UPDATE api_keys SET is_admin = 1 WHERE id = ?").bind(getTestAgentId()).run();
  const response = await post('keys', { name: 'test-agent' });
  expect(response.status).toBe(409);
  expect(await response.text()).toBe('agent name already exists');
});
