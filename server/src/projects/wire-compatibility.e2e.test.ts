// Protects the pre-3b native wire contract across boss and agent requests.
// Uses real Worker/D1 responses and runtime decoding of legacy scalar fields.
import { SELF } from 'cloudflare:test';
import { beforeAll, expect, it } from 'vitest';
import { authHeaders, seedBossToken, seedDatabase } from '../test-helpers';
import { isRecord } from '../routes/progress-helpers';

const request = (path: string, token?: string): Promise<Response> => SELF.fetch(
  `https://test.local/api/${path}`, { headers: token ? { Authorization: `Bearer ${token}` } : authHeaders() },
);

// Like the old HibossKit Decodable model, reject non-string required fields.
function decodeLegacyPost(value: unknown): { id: string; project: string } {
  if (!isRecord(value) || typeof value.id !== 'string' || typeof value.project !== 'string'
    || typeof value.agent_id !== 'string' || typeof value.body !== 'string'
    || typeof value.created_at !== 'string') throw new Error('invalid legacy ProgressPost');
  return { id: value.id, project: value.project };
}

beforeAll(async () => {
  await seedDatabase();
  await seedBossToken('Wire Admin', 'admin', 'wire-admin');
  const response = await SELF.fetch('https://test.local/api/progress', {
    method: 'POST', headers: authHeaders(), body: JSON.stringify({ project: 'summary-repo', body: 'Summary' }),
  });
  expect(response.status).toBe(201);
});

it.each([undefined, 'wire-admin'])('decodes old ProgressPost fields for auth %s', async token => {
  const created = await SELF.fetch('https://test.local/api/progress', {
    method: 'POST', headers: authHeaders(), body: JSON.stringify({ project: 'wire-repo', body: 'Done' }),
  });
  expect(created.status).toBe(201);
  const fixture: unknown = await created.json();
  const oldPost = decodeLegacyPost(fixture);
  const detail = await request(`progress/${oldPost.id}`, token);
  expect(detail.status).toBe(200);
  const detailFixture: unknown = await detail.json();
  expect(decodeLegacyPost(detailFixture)).toEqual(oldPost);
  const response = await request('progress?project=wire-repo', token);
  const feed: unknown = await response.json();
  if (!isRecord(feed) || !Array.isArray(feed.posts)) throw new Error('invalid feed');
  expect(feed.posts.map(decodeLegacyPost)).toContainEqual(oldPost);
  for (const post of [fixture, detailFixture, ...feed.posts]) {
    expect(post).toMatchObject({ project: 'wire-repo', project_ref: {
      id: expect.any(String), slug: 'wire-repo', display_name: 'wire-repo',
    } });
  }
});

it('keeps scalar session fields beside project_ref on registration and both inventories', async () => {
  const created = await SELF.fetch('https://test.local/api/sessions', {
    method: 'POST', headers: authHeaders(), body: JSON.stringify({ id: 'wire-session', project: 'session-repo' }),
  });
  expect(created.status).toBe(201);
  expect(await created.json()).toMatchObject({ project_slug: 'session-repo', project_id: expect.any(String),
    project_ref: { id: expect.any(String), slug: 'session-repo', display_name: 'session-repo' } });
  for (const [path, token] of [['sessions', undefined], ['sessions', 'wire-admin'], ['boss/sessions', 'wire-admin']] as const) {
    const response = await request(path, token);
    expect(response.status).toBe(200);
    const data: unknown = await response.json();
    if (!isRecord(data) || !Array.isArray(data.sessions)) throw new Error('invalid sessions');
    expect(data.sessions).toContainEqual(expect.objectContaining({ id: 'wire-session', project_slug: 'session-repo',
      project_id: expect.any(String), project_ref: { id: expect.any(String), slug: 'session-repo', display_name: 'session-repo' } }));
  }
});

it.each([undefined, 'wire-admin'])('preserves project summary scalars for auth %s', async token => {
  const response = await request('progress/projects', token);
  expect(response.status).toBe(200);
  const data: unknown = await response.json();
  if (!isRecord(data) || !Array.isArray(data.projects)) throw new Error('invalid projects');
  expect(data.projects.length).toBeGreaterThan(0);
  for (const project of data.projects) {
    if (!isRecord(project) || typeof project.project !== 'string' || typeof project.count !== 'number'
      || typeof project.agent_id !== 'string'
      || !(project.last_post_at === null || typeof project.last_post_at === 'string')) {
      throw new Error('invalid legacy ProgressProject');
    }
    expect(project.project_ref).toMatchObject({ slug: project.project, id: expect.any(String), display_name: expect.any(String) });
  }
});

it.each([undefined, 'wire-admin'])('retains team profile project strings for auth %s', async token => {
  const response = await request('progress/teams/summary-repo', token);
  expect(response.status).toBe(200);
  expect(await response.json()).toMatchObject({ project: 'summary-repo', project_ref: {
    id: expect.any(String), slug: 'summary-repo', display_name: 'summary-repo',
  } });
  const listing = await request('progress/teams', token);
  expect(await listing.json()).toMatchObject({ teams: expect.arrayContaining([
    expect.objectContaining({ project: 'summary-repo', project_ref: expect.objectContaining({ slug: 'summary-repo' }) }),
  ]) });
});
