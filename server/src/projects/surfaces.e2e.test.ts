// Verifies project administration, retired text storage and alias profile APIs.
// Drives the Worker with boss/agent credentials against real D1 migrations.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, seedBossToken, seedDatabase } from '../test-helpers';
import { resolveDestinations } from '../delivery/destinations';

beforeAll(seedDatabase);
const request = (path: string, method = 'GET', body?: unknown, token?: string): Promise<Response> =>
  SELF.fetch(`https://test.local/api/${path}`, { method,
    headers: token ? { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' } : authHeaders(),
    body: body === undefined ? undefined : JSON.stringify(body) });

it('requires project identity for new sessions but retains identity on re-registration', async () => {
  expect((await request('sessions', 'POST', { id: 'unlinked' })).status).toBe(400);
  expect((await request('sessions', 'POST', { id: 'linked', project: 'checkout' })).status).toBe(201);
  expect((await request('sessions', 'POST', { id: 'linked' })).status).toBe(201);
});

it('reads aliases, writes project profiles and leaves post text empty', async () => {
  await request('progress', 'POST', { body: 'identity', project_identity: { slug: 'canonical', aliases: ['alias'] } });
  expect((await request('progress/teams/alias', 'PUT', { display_name: 'Renamed' })).status).toBe(200);
  const profile = await request('progress/teams/alias');
  expect(await profile.json()).toMatchObject({ project: 'canonical', display_name: 'Renamed' });
  expect(await env.DB.prepare("SELECT project FROM progress_posts WHERE body = 'identity'").first('project')).toBeNull();
  expect(await env.DB.prepare("SELECT name FROM sqlite_master WHERE name = 'progress_teams'").first()).toBeNull();
});

it('lists, renames and merges projects with boss audit and scoped counts', async () => {
  await seedBossToken('Project Admin', 'admin', 'project-admin');
  await request('sessions', 'POST', { id: 'merge-session', project: 'source', branch: 'main' });
  await request('progress', 'POST', { body: 'source post', project: 'source' });
  await request('progress', 'POST', { body: 'target post', project: 'target' });
  const listing = await request('boss/projects', 'GET', undefined, 'project-admin');
  const { projects } = await listing.json() as { projects: { id: string; slug: string; session_count: number }[] };
  const source = projects.find(p => p.slug === 'source');
  const target = projects.find(p => p.slug === 'target');
  if (!source || !target) throw new Error('missing project inventory');
  expect(source.session_count).toBe(1);
  expect((await request(`boss/projects/${target.id}`, 'PATCH', { display_name: 'Target' }, 'project-admin')).status).toBe(200);
  expect((await request(`boss/projects/${source.id}`, 'PATCH', { merge_into: target.id }, 'project-admin')).status).toBe(200);
  expect(await env.DB.prepare("SELECT project_id FROM sessions WHERE id = 'merge-session'").first('project_id')).toBe(target.id);
  expect(await env.DB.prepare("SELECT actor_type FROM audit_log WHERE action = 'project.merge' AND resource_id = ?").bind(target.id).first('actor_type')).toBe('boss');
  const feed = await request('progress?project=source', 'GET', undefined, 'project-admin');
  const { posts } = await feed.json() as { posts: { project: { id: string; slug: string } }[] };
  expect(posts).toHaveLength(2);
  expect(posts[0].project).toMatchObject({ id: target.id, slug: 'target' });
});

it('rejects viewer mutations and alias collisions without merging implicitly', async () => {
  await seedBossToken('Project Viewer', 'viewer', 'project-viewer');
  expect((await request('boss/projects/missing', 'PATCH', { display_name: 'No' }, 'project-viewer')).status).toBe(403);
  await request('progress', 'POST', { body: 'a', project: 'alias-a' });
  await request('progress', 'POST', { body: 'b', project: 'alias-b' });
  expect((await request('projects/alias-a/aliases', 'POST', { alias: 'alias-b' })).status).toBe(409);
  expect((await request('projects/alias-a/aliases', 'POST', { alias: 'extra-alias' })).status).toBe(201);
  expect((await request('projects/alias-a/aliases/extra-alias', 'DELETE')).status).toBe(204);
  expect((await request('projects/alias-a/aliases/alias-a', 'DELETE')).status).toBe(400);
});

it('scopes boss inventory and exposes canonical session fields even for inactive history', async () => {
  const boss = await seedBossToken('Scoped', 'manager', 'scoped-projects');
  await env.DB.prepare('INSERT INTO boss_agent_access (boss_id, agent_id) VALUES (?, ?)').bind(boss, 'test-agent-id').run();
  await request('sessions', 'POST', { id: 'scoped-session', project: 'scoped-repo', branch: 'feat/a' });
  await env.DB.prepare("UPDATE sessions SET label = 'obsolete/main', last_seen_at = '2000-01-01' WHERE id = 'scoped-session'").run();
  const response = await request('boss/sessions?include_inactive=true', 'GET', undefined, 'scoped-projects');
  const { sessions } = await response.json() as { sessions: { id: string; project_id: string; project_slug: string; label: string }[] };
  expect(sessions.find(s => s.id === 'scoped-session')).toMatchObject({ project_slug: 'scoped-repo', label: 'scoped-repo/feat/a', project_id: expect.any(String) });
  await env.DB.prepare("INSERT INTO projects (id, slug, display_name) VALUES ('invisible', 'invisible', 'Invisible')").run();
  const listing = await request('boss/projects', 'GET', undefined, 'scoped-projects');
  const { projects } = await listing.json() as { projects: { slug: string }[] };
  expect(projects.some(p => p.slug === 'invisible')).toBe(false);
  expect((await request('boss/projects/invisible', 'PATCH', { display_name: 'No' }, 'scoped-projects')).status).toBe(404);
});

it('routes by project IDs and retains target routes when explicitly merging', async () => {
  await seedBossToken('Route Admin', 'admin', 'route-admin', 'route-admin');
  await request('sessions', 'POST', { id: 'route-session', project: 'route-source' });
  await request('progress', 'POST', { body: 'route-target', project: 'route-target' });
  const source = await env.DB.prepare("SELECT id FROM projects WHERE slug = 'route-source'").first<string>('id');
  const target = await env.DB.prepare("SELECT id FROM projects WHERE slug = 'route-target'").first<string>('id');
  if (!source || !target) throw new Error('missing route projects');
  await env.DB.prepare("INSERT INTO boss_destinations (id, boss_id, kind, label, target) VALUES ('route-dest', 'route-admin', 'discord_channel', 'Route', '{}')").run();
  await env.DB.prepare("INSERT INTO destination_routes (id, destination_id, project_id, external_channel_id) VALUES ('source-route', 'route-dest', ?, 'source-channel'), ('target-route', 'route-dest', ?, 'target-channel')").bind(source, target).run();
  const message = { agent_id: 'test-agent-id', direction: 'agent_to_boss' as const, priority: 'normal' as const, session_id: 'route-session' };
  const before = await resolveDestinations(env, message);
  expect(before.find(d => d.id === 'route-dest')?.config.channel_id).toBe('source-channel');
  expect((await request(`boss/projects/${source}`, 'PATCH', { merge_into: target }, 'route-admin')).status).toBe(200);
  const after = await resolveDestinations(env, { ...message, project: 'route-source' });
  expect(after.find(d => d.id === 'route-dest')?.config.channel_id).toBe('target-channel');
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM destination_routes WHERE destination_id = 'route-dest'").first('n')).toBe(1);
});
