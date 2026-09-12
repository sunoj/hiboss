// Exercises project identity through the deployed Worker API surface.
// Covers aliases, legacy clients, profiles, and session ownership using D1.
import { env, SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, seedDatabase, getTestAgentId } from '../test-helpers';

beforeAll(seedDatabase);
const post = (path: string, body: Record<string, unknown>): Promise<Response> => SELF.fetch(`https://test.local/api/${path}`, {
  method: 'POST', headers: authHeaders(), body: JSON.stringify(body),
});

it('keeps a renamed checkout, legacy posts, sessions and profiles on one project', async () => {
  const session = await post('sessions', { id: 'project-session', branch: 'main', project: { slug: 'repo', aliases: ['old-checkout'] } });
  expect(session.status).toBe(201);
  const renamed = await post('progress', { body: 'renamed', session_id: 'project-session', project: { slug: 'repo', aliases: ['new-checkout'] } });
  expect(renamed.status).toBe(201);
  expect((await renamed.json() as { project: string }).project).toBe('repo');
  const legacy = await post('progress', { body: 'legacy', project: 'new-checkout' });
  expect(legacy.status).toBe(201);
  expect((await legacy.json() as { project: string }).project).toBe('repo');
  const profile = await SELF.fetch('https://test.local/api/progress/teams/old-checkout', {
    method: 'PUT', headers: authHeaders(), body: JSON.stringify({ display_name: 'The Repo', handle: 'repo-team' }),
  });
  expect(profile.status).toBe(200);
  const rows = await env.DB.prepare('SELECT DISTINCT project_id FROM progress_posts WHERE body IN (?, ?)').bind('renamed', 'legacy').all();
  expect(rows.results).toHaveLength(1);
  const stored = await env.DB.prepare('SELECT project_id, label FROM sessions WHERE id = ?').bind('project-session').first();
  expect(stored).toMatchObject({ ...rows.results[0], label: 'repo/main' });
  expect(await env.DB.prepare("SELECT name FROM sqlite_master WHERE name = 'progress_teams'").first()).toBeNull();
});

it('resolves old session labels with and without a branch', async () => {
  for (const label of ['legacy-repo/main', 'legacy-repo']) {
    const response = await post('sessions', { id: label, label });
    expect(response.status).toBe(201);
  }
  const rows = await env.DB.prepare("SELECT DISTINCT project_id FROM sessions WHERE id LIKE 'legacy-repo%'").all();
  expect(rows.results).toHaveLength(1);
  expect(rows.results[0].project_id).toBeTruthy();
});

it('rejects foreign and missing sessions before creating projects, posts or messages', async () => {
  await env.DB.prepare("INSERT INTO api_keys (id, name, key_hash) VALUES ('other-owner', 'other-owner', 'other-owner')").run();
  await env.DB.prepare("INSERT INTO sessions (id, agent_id) VALUES ('foreign-session', 'other-owner')").run();
  for (const session_id of ['foreign-session', 'missing-session']) {
    for (const path of ['messages', 'progress']) {
      const response = await post(path, { body: 'invalid owner', session_id, project: 'should-not-exist' });
      expect(response.status).toBe(400);
    }
  }
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM projects WHERE slug = 'should-not-exist'").first('n')).toBe(0);
});

it('merges aliases joining two existing projects into the presented slug', async () => {
  await post('progress', { body: 'a', project: 'identity-a' });
  await post('progress', { body: 'b', project: 'identity-b' });
  const response = await post('progress', { body: 'conflict', project: { slug: 'identity-a', aliases: ['identity-b'] } });
  expect(response.status).toBe(201);
  expect((await response.json() as { project: string }).project).toBe('identity-a');
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM projects WHERE slug = 'identity-b'").first('n')).toBe(0);
});

it('enforces unique agent names in D1', async () => {
  await expect(env.DB.prepare('INSERT INTO api_keys (id, name, key_hash) SELECT ?, name, ? FROM api_keys WHERE id = ?')
    .bind('duplicate-agent', 'duplicate-hash', getTestAgentId()).run()).rejects.toThrow(/UNIQUE/);
});

it('handles concurrent first sight without leaving orphan projects', async () => {
  const requests = await Promise.all(Array.from({ length: 3 }, (_, index) => post('progress', {
    body: `concurrent-${index}`, project: { slug: 'concurrent-repo', aliases: [`concurrent-checkout-${index}`] },
  })));
  expect(requests.map(response => response.status)).toEqual([201, 201, 201]);
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM projects WHERE slug = 'concurrent-repo'").first('n')).toBe(1);
  expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM project_aliases WHERE alias LIKE 'concurrent-checkout-%'").first('n')).toBe(3);
});

it('lists session-only projects and filters posts using aliases', async () => {
  await post('sessions', { id: 'only-session', project: { slug: 'only-session-repo', aliases: ['only-session-cwd'] } });
  const response = await SELF.fetch('https://test.local/api/progress/projects', { headers: authHeaders() });
  expect(response.status).toBe(200);
  const data = await response.json() as { projects: { project: string; count: number; last_post_at: string | null }[] };
  expect(data.projects).toContainEqual(expect.objectContaining({ project: 'only-session-repo', count: 0, last_post_at: null }));
  await post('progress', { body: 'filter me', project: { slug: 'filter-repo', aliases: ['filter-cwd'] } });
  const feed = await SELF.fetch('https://test.local/api/progress?project=filter-cwd', { headers: authHeaders() });
  const posts = await feed.json() as { posts: { project: string; body: string }[] };
  expect(posts.posts).toHaveLength(1);
  expect(posts.posts[0]).toMatchObject({ project: 'filter-repo', body: 'filter me' });
});

it('rejects malformed project objects', async () => {
  for (const project of [{ slug: '', aliases: [] }, { slug: 'valid', aliases: [7] }, { slug: 'valid', aliases: [], repo_url: false }]) {
    for (const endpoint of ['progress', 'sessions']) {
      const response = await post(endpoint, { id: 'invalid-project', body: 'bad project', project });
      expect(response.status).toBe(400);
    }
  }
});

it('uses project FKs for Home even when stored labels and post text differ', async () => {
  const { seedBossToken } = await import('../test-helpers');
  const token = 'project-home-boss';
  await seedBossToken('Project Home', 'admin', token);
  await post('sessions', { id: 'home-project-session', branch: 'feature/a', status: 'blocked', project: { slug: 'home-canonical', aliases: ['home-checkout'] } });
  await post('progress', { body: 'Home entity post', session_id: 'home-project-session', project: 'home-checkout' });
  await env.DB.prepare("UPDATE sessions SET label = 'old-home-name/feature/a' WHERE id = 'home-project-session'").run();
  await env.DB.prepare("UPDATE progress_posts SET project = 'old-home-post-name' WHERE session_id = 'home-project-session'").run();
  const response = await SELF.fetch('https://test.local/api/boss/home', { headers: { Authorization: `Bearer ${token}` } });
  expect(response.status).toBe(200);
  const home = await response.json() as { projects: { name: string; postCount7d: number; sessions: { blocked: number } }[]; attention: { sessionId?: string; project: string }[] };
  expect(home.projects).toContainEqual(expect.objectContaining({ name: 'home-canonical', postCount7d: 1, sessions: expect.objectContaining({ blocked: 1 }) }));
  expect(home.projects.some(project => project.name.startsWith('old-home'))).toBe(false);
  expect(home.attention.find(item => item.sessionId === 'home-project-session')?.project).toBe('home-canonical');
  const sessions = await SELF.fetch('https://test.local/api/sessions', { headers: authHeaders() });
  const listed = await sessions.json() as { sessions: { id: string; label: string }[] };
  expect(listed.sessions.find(row => row.id === 'home-project-session')?.label).toBe('home-canonical/feature/a');
});

it('prefers an exact agent name over an ID prefix', async () => {
  await env.DB.prepare("INSERT INTO api_keys (id, name, key_hash) VALUES ('named-recipient', 'ambiguous-agent', 'named-hash'), ('ambiguous-agent-id', 'prefix-agent', 'prefix-hash')").run();
  const response = await post('messages', { body: 'named delivery', to: 'ambiguous-agent' });
  expect(response.status).toBe(201);
  const body = await response.json() as { id: string };
  expect(await env.DB.prepare('SELECT target_agent_id FROM messages WHERE id = ?').bind(body.id).first('target_agent_id')).toBe('named-recipient');
});
